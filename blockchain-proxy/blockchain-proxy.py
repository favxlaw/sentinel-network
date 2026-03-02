import os
from dotenv import load_dotenv
import json
import logging
import hashlib
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, List
from abc import ABC, abstractmethod
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel
from web3 import Web3
from web3.providers import HTTPProvider
from pydantic import Field

# FastAPI app
app = FastAPI(title="Blockchain Proxy Service")

load_dotenv()

RPC_PROVIDER = os.getenv('RPC_PROVIDER', 'alchemy')
ALCHEMY_API_KEY = os.getenv('ALCHEMY_API_KEY', '')
INFURA_API_KEY = os.getenv('INFURA_API_KEY', '')
CACHE_TTL_SECONDS = int(os.getenv('CACHE_TTL_SECONDS', '300'))
CACHE_BACKEND = os.getenv('CACHE_BACKEND', 'memory')
REDIS_URL = os.getenv('REDIS_URL', 'redis://localhost:6379/0')
LOG_DIR = os.getenv('LOG_DIR', './logs')

os.makedirs(LOG_DIR, exist_ok=True)


def get_rpc_url() -> str:
    """Get RPC endpoint URL based on provider"""
    if RPC_PROVIDER == 'alchemy':
        if not ALCHEMY_API_KEY:
            raise ValueError("ALCHEMY_API_KEY not set")
        return f"https://eth-sepolia.g.alchemy.com/v2/{ALCHEMY_API_KEY}"
    elif RPC_PROVIDER == 'infura':
        if not INFURA_API_KEY:
            raise ValueError("INFURA_API_KEY not set")
        return f"https://sepolia.infura.io/v3/{INFURA_API_KEY}"
    else:
        raise ValueError(f"Unknown RPC_PROVIDER: {RPC_PROVIDER}")


# Initialize Web3 instance
rpc_url = get_rpc_url()
w3 = Web3(HTTPProvider(rpc_url))


# ABSTRACT CACHE BACKEND
class CacheBackend(ABC):
    """Abstract base class for cache backends"""
    
    @abstractmethod
    def get(self, key: str) -> Optional[Any]:
        """Retrieve value from cache"""
        pass
    
    @abstractmethod
    def set(self, key: str, value: Any, ttl_seconds: int):
        """Store value in cache with TTL"""
        pass
    
    @abstractmethod
    def clear(self):
        """Clear all cached data"""
        pass
    
    @abstractmethod
    def stats(self) -> Dict[str, Any]:
        """Get cache statistics"""
        pass


# IN-MEMORY CACHE BACKEND
class InMemoryCacheBackend(CacheBackend):
    """In-memory cache backend using Python dict"""
    
    def __init__(self):
        self.cache: Dict[str, Dict[str, Any]] = {}
    
    def get(self, key: str) -> Optional[Any]:
        """Retrieve value from in-memory cache"""
        if key in self.cache:
            entry = self.cache[key]
            # Check if still fresh
            if datetime.now() < entry['expires_at']:
                return entry['data']
            else:
                # Expired, remove it
                del self.cache[key]
        return None
    
    def set(self, key: str, value: Any, ttl_seconds: int):
        """Store value in in-memory cache"""
        self.cache[key] = {
            'data': value,
            'expires_at': datetime.now() + timedelta(seconds=ttl_seconds)
        }
    
    def clear(self):
        """Clear all in-memory cache"""
        self.cache.clear()
    
    def stats(self) -> Dict[str, Any]:
        """Get in-memory cache statistics"""
        # Clean up expired entries
        current_time = datetime.now()
        expired_keys = [
            key for key, entry in self.cache.items()
            if current_time >= entry['expires_at']
        ]
        for key in expired_keys:
            del self.cache[key]
        
        return {
            'backend': 'memory',
            'total_entries': len(self.cache),
            'connected': True
        }


# REDIS CACHE BACKEND
class RedisCacheBackend(CacheBackend):
    """Redis cache backend using redis-py"""
    
    def __init__(self, redis_url: str):
        try:
            import redis
            self.redis_client = redis.from_url(redis_url, decode_responses=True)
            # Test connection
            self.redis_client.ping()
            self.connected = True
        except Exception as e:
            logging.error(f"Failed to connect to Redis: {e}")
            self.redis_client = None
            self.connected = False
    
    def get(self, key: str) -> Optional[Any]:
        """Retrieve value from Redis cache"""
        if not self.connected or not self.redis_client:
            return None
        
        try:
            value = self.redis_client.get(key)
            if value:
                return json.loads(value)
            return None
        except Exception as e:
            logging.error(f"Redis GET error: {e}")
            return None
    
    def set(self, key: str, value: Any, ttl_seconds: int):
        """Store value in Redis cache with TTL"""
        if not self.connected or not self.redis_client:
            return
        
        try:
            serialized = json.dumps(value)
            self.redis_client.setex(key, ttl_seconds, serialized)
        except Exception as e:
            logging.error(f"Redis SET error: {e}")
    
    def clear(self):
        """Clear all Redis cache (flushes current database)"""
        if not self.connected or not self.redis_client:
            return
        
        try:
            self.redis_client.flushdb()
        except Exception as e:
            logging.error(f"Redis CLEAR error: {e}")
    
    def stats(self) -> Dict[str, Any]:
        """Get Redis cache statistics"""
        if not self.connected or not self.redis_client:
            return {
                'backend': 'redis',
                'connected': False,
                'error': 'Redis connection not available'
            }
        
        try:
            info = self.redis_client.info('stats')
            dbsize = self.redis_client.dbsize()
            
            return {
                'backend': 'redis',
                'connected': True,
                'total_entries': dbsize,
                'total_commands_processed': info.get('total_commands_processed', 0),
                'keyspace_hits': info.get('keyspace_hits', 0),
                'keyspace_misses': info.get('keyspace_misses', 0)
            }
        except Exception as e:
            logging.error(f"Redis STATS error: {e}")
            return {
                'backend': 'redis',
                'connected': False,
                'error': str(e)
            }


# CACHE BACKEND FACTORY
def create_cache_backend(backend_type: str, redis_url: str = None) -> CacheBackend:
    """function to create cache backend"""
    if backend_type == 'redis':
        return RedisCacheBackend(redis_url)
    elif backend_type == 'memory':
        return InMemoryCacheBackend()
    else:
        raise ValueError(f"Unknown cache backend: {backend_type}")


# BLOCKCHAIN CACHE (with backend abstraction)
class BlockchainCache:
    """
    Smart cache that only stores immutable blockchain data
    - Old blocks: CACHE (never change)
    - Latest block: DON'T CACHE (changes every ~12s)
    
    Now backend-agnostic: works with any CacheBackend implementation
    """
    
    def __init__(self, backend: CacheBackend, ttl_seconds: int = 300):
        self.backend = backend
        self.ttl_seconds = ttl_seconds
        
        # Methods that return immutable data (safe to cache)
        self.cacheable_methods = {
            'eth_getBlockByNumber',      # Old blocks don't change
            'eth_getBlockByHash',         # Hash is unique identifier
            'eth_getTransactionByHash',   # Transaction is final
            'eth_getTransactionReceipt',  # Receipt is final
            'eth_getUncleByBlockHashAndIndex',
            'eth_getUncleByBlockNumberAndIndex',
        }
    
    def _generate_key(self, tenant_id: str, method: str, params: List) -> str:
        """
        Create unique cache key from tenant + method + params
        
        Tenant namespacing prevents cache collisions between tenants
        """
        cache_data = {
            'tenant': tenant_id,
            'method': method,
            'params': params
        }
        json_str = json.dumps(cache_data, sort_keys=True)
        hash_key = hashlib.sha256(json_str.encode()).hexdigest()
        # Prefix with tenant for easier debugging
        return f"{tenant_id}:{method}:{hash_key}"
    
    def _is_cacheable(self, method: str, params: List) -> bool:
        """
        Determine if this request should be cached
        
        Examples:
        - eth_getBlockByNumber with "0x100" → YES (specific old block)
        - eth_getBlockByNumber with "latest" → NO (dynamic)
        - eth_blockNumber → NO (always changing)
        """
        if method not in self.cacheable_methods:
            return False
        
        # Don't cache requests with dynamic parameters
        if params:
            param_str = str(params[0]).lower()
            if param_str in ['latest', 'pending', 'earliest']:
                return False
        
        return True
    
    def get(self, tenant_id: str, method: str, params: List) -> Optional[Any]:
        """Try to retrieve from cache"""
        if not self._is_cacheable(method, params):
            return None
        
        key = self._generate_key(tenant_id, method, params)
        return self.backend.get(key)
    
    def set(self, tenant_id: str, method: str, params: List, data: Any):
        """Store in cache"""
        if not self._is_cacheable(method, params):
            return
        
        key = self._generate_key(tenant_id, method, params)
        self.backend.set(key, data, self.ttl_seconds)
    
    def clear(self):
        """Clear all cache"""
        self.backend.clear()
    
    def stats(self) -> Dict[str, Any]:
        """Get cache statistics"""
        backend_stats = self.backend.stats()
        return {
            **backend_stats,
            'cacheable_methods': list(self.cacheable_methods),
            'ttl_seconds': self.ttl_seconds
        }


# Initialize cache with appropriate backend
cache_backend = create_cache_backend(CACHE_BACKEND, REDIS_URL)
cache = BlockchainCache(backend=cache_backend, ttl_seconds=CACHE_TTL_SECONDS)


# TENANT LOGGING
def get_tenant_logger(tenant_id: str) -> logging.Logger:
    """
    Get or create tenant-specific logger
    Each tenant gets their own log file: logs/dao-alpha.log
    """
    logger_name = f"tenant.{tenant_id}"
    logger = logging.getLogger(logger_name)
    
    if not logger.handlers:
        logger.setLevel(logging.INFO)
        
        # Create tenant log file
        log_file = os.path.join(LOG_DIR, f"{tenant_id}.log")
        handler = logging.FileHandler(log_file)
        handler.setLevel(logging.INFO)
        
        # Log format: timestamp - tenant - level - message
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        handler.setFormatter(formatter)
        logger.addHandler(handler)
    
    return logger


# TENANT VALIDATION
ALLOWED_TENANTS = ['dao-alpha', 'dao-beta', 'dao-gamma']


def validate_tenant(tenant_id: str) -> bool:
    """Check if tenant is authorized"""
    return tenant_id in ALLOWED_TENANTS


# REQUEST/RESPONSE MODELS
class RPCRequest(BaseModel):
    """Standard JSON-RPC 2.0 request format"""
    jsonrpc: str = "2.0"
    method: str
    params: List = Field(default_factory=list)
    id: int = 1


class RPCResponse(BaseModel):
    """Standard JSON-RPC 2.0 response format"""
    jsonrpc: str = "2.0"
    id: int
    result: Optional[Any] = None
    error: Optional[Dict[str, Any]] = None


# API ENDPOINTS
@app.get("/health")
async def health_check():
    """
    Health check endpoint
    Returns: service status, Web3 connection status, cache backend info
    """
    is_connected = w3.is_connected()
    cache_stats = cache.stats()
    
    # Extract cache backend info
    cache_backend_type = cache_stats.get('backend', 'unknown')
    cache_connected = cache_stats.get('connected', False)
    
    health_status = {
        "status": "healthy" if is_connected else "unhealthy",
        "service": "blockchain-proxy",
        "web3_connected": is_connected,
        "provider": RPC_PROVIDER,
        "cache": {
            "backend": cache_backend_type,
            "connected": cache_connected,
            "stats": cache_stats
        },
        "timestamp": datetime.now().isoformat()
    }
    
    # Add Redis-specific info if using Redis backend
    if cache_backend_type == 'redis':
        health_status["cache"]["redis_url"] = REDIS_URL.split('@')[-1] if '@' in REDIS_URL else REDIS_URL.split('//')[1]
    
    return health_status


@app.post("/rpc", response_model=RPCResponse)
async def proxy_rpc(
    rpc_request: RPCRequest,
    x_tenant_id: Optional[str] = Header(None)
):
    """
    Main proxy endpoint - forwards JSON-RPC requests to blockchain
    
    Flow:
    1. Validate tenant
    2. Check cache (tenant-namespaced)
    3. Forward to blockchain (if not cached)
    4. Store in cache (if cacheable)
    5. Log everything
    6. Return response
    """
    # Validate tenant header
    if not x_tenant_id:
        raise HTTPException(
            status_code=400, 
            detail="Missing X-Tenant-ID header"
        )
    
    if not validate_tenant(x_tenant_id):
        raise HTTPException(
            status_code=403,
            detail=f"Invalid tenant: {x_tenant_id}"
        )
    
    # Get tenant logger
    logger = get_tenant_logger(x_tenant_id)
    
    method = rpc_request.method
    params = rpc_request.params
    
    logger.info(f"RPC Request - Method: {method}, Params: {params}")
    
    # Check cache (with tenant namespacing)
    cached_result = cache.get(x_tenant_id, method, params)
    if cached_result is not None:
        logger.info(f"Cache HIT - {method}")
        return RPCResponse(
            jsonrpc="2.0",
            id=rpc_request.id,
            result=cached_result
        )
    
    logger.info(f"Cache MISS - {method}")
    
    # Forward request to blockchain via Web3.py
    try:
        # Web3's provider to make raw JSON-RPC request
        response = w3.provider.make_request(method, params)
        
        if 'error' in response:
            logger.error(f"RPC Error - {response['error']}")
            return RPCResponse(
                jsonrpc="2.0",
                id=rpc_request.id,
                error=response['error']
            )
        
        result = response.get('result')
        
        # Cache if applicable (with tenant namespacing)
        cache.set(x_tenant_id, method, params, result)
        if cache.get(x_tenant_id, method, params) is not None:
            logger.info(f"Cached response - {method}")
        
        logger.info(f"RPC Success - {method}")
        
        return RPCResponse(
            jsonrpc="2.0",
            id=rpc_request.id,
            result=result
        )
        
    except Exception as e:
        logger.error(f"RPC Request Failed - {str(e)}")
        raise HTTPException(
            status_code=500,
            detail=f"Blockchain request failed: {str(e)}"
        )


@app.get("/cache/stats")
async def get_cache_stats():
    """Get detailed cache statistics"""
    return cache.stats()


@app.post("/cache/clear")
async def clear_cache():
    """Clear all cached data"""
    cache.clear()
    return {"status": "cache cleared", "timestamp": datetime.now().isoformat()}


@app.get("/web3/info")
async def web3_info():
    """Get Web3 connection information"""
    try:
        is_connected = w3.is_connected()
        chain_id = w3.eth.chain_id if is_connected else None
        latest_block = w3.eth.block_number if is_connected else None
        
        return {
            "connected": is_connected,
            "provider": RPC_PROVIDER,
            "rpc_url": rpc_url.split('/')[-2] + "/***",  
            "chain_id": chain_id,
            "latest_block": latest_block
        }
    except Exception as e:
        return {
            "connected": False,
            "error": str(e)
        }


# STARTUP
@app.lifespan("startup")
async def startup_event():
    """Verify Web3 and cache connections on startup"""
    print(f"=== Blockchain Proxy Service ===")
    
    # Web3 connection
    if w3.is_connected():
        print(f"✓ Connected to Ethereum via {RPC_PROVIDER}")
        print(f"  Chain ID: {w3.eth.chain_id}")
        print(f"  Latest Block: {w3.eth.block_number}")
    else:
        print(f"✗ Failed to connect to {RPC_PROVIDER}")
        print(f"  Check your API key in .env file")
    
    # Cache backend info
    cache_stats = cache.stats()
    cache_backend_type = cache_stats.get('backend', 'unknown')
    cache_connected = cache_stats.get('connected', False)
    
    print(f"✓ Cache Backend: {cache_backend_type}")
    if cache_backend_type == 'redis':
        if cache_connected:
            print(f"  ✓ Redis connected: {REDIS_URL.split('@')[-1] if '@' in REDIS_URL else REDIS_URL.split('//')[1]}")
        else:
            print(f"  ✗ Redis connection failed")
            print(f"    URL: {REDIS_URL}")
    else:
        print(f"  In-memory cache (local development)")
    
    print(f"  TTL: {CACHE_TTL_SECONDS} seconds")
    print(f"================================")


# if __name__ == '__main__':
#     import uvicorn
#     port = int(os.getenv('PORT', '8000'))
#     uvicorn.run(app, host='0.0.0.0', port=port)