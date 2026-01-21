import os
from dotenv import load_dotenv
import json
import logging
import hashlib
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, List
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel
from web3 import Web3
from web3.providers import HTTPProvider

# FastAPI app
app = FastAPI(title="Blockchain Proxy Service")

load_dotenv()

RPC_PROVIDER = os.getenv('RPC_PROVIDER', 'alchemy')
ALCHEMY_API_KEY = os.getenv('ALCHEMY_API_KEY', '')
INFURA_API_KEY = os.getenv('INFURA_API_KEY', '')
CACHE_TTL_SECONDS = int(os.getenv('CACHE_TTL_SECONDS', '300'))
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


# CACHE CLASS
class BlockchainCache:
    """
    Smart cache that only stores immutable blockchain data
    - Old blocks: CACHE (never change)
    - Latest block: DON'T CACHE (changes every ~12s)
    """
    
    def __init__(self, ttl_seconds: int = 300):
        self.cache: Dict[str, Dict[str, Any]] = {}
        self.ttl = timedelta(seconds=ttl_seconds)
        
        # Methods that return immutable data (safe to cache)
        self.cacheable_methods = {
            'eth_getBlockByNumber',      # Old blocks don't change
            'eth_getBlockByHash',         # Hash is unique identifier
            'eth_getTransactionByHash',   # Transaction is final
            'eth_getTransactionReceipt',  # Receipt is final
            'eth_getUncleByBlockHashAndIndex',
            'eth_getUncleByBlockNumberAndIndex',
        }
    
    def _generate_key(self, method: str, params: List) -> str:
        """Create unique cache key from method + params"""
        cache_data = {
            'method': method,
            'params': params
        }
        json_str = json.dumps(cache_data, sort_keys=True)
        return hashlib.sha256(json_str.encode()).hexdigest()
    
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
    
    def get(self, method: str, params: List) -> Optional[Any]:
        """Try to retrieve from cache"""
        if not self._is_cacheable(method, params):
            return None
        
        key = self._generate_key(method, params)
        
        if key in self.cache:
            entry = self.cache[key]
            # Check if still fresh
            if datetime.now() - entry['timestamp'] < self.ttl:
                return entry['data']
            else:
                # Expired, remove it
                del self.cache[key]
        
        return None
    
    def set(self, method: str, params: List, data: Any):
        """Store in cache"""
        if not self._is_cacheable(method, params):
            return
        
        key = self._generate_key(method, params)
        self.cache[key] = {
            'data': data,
            'timestamp': datetime.now()
        }
    
    def clear(self):
        """Clear all cache"""
        self.cache.clear()
    
    def stats(self) -> Dict[str, Any]:
        """Get cache statistics"""
        return {
            'total_entries': len(self.cache),
            'cacheable_methods': list(self.cacheable_methods),
            'ttl_seconds': self.ttl.total_seconds()
        }

# Initialize cache
cache = BlockchainCache(ttl_seconds=CACHE_TTL_SECONDS)


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
    params: List = []
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
    Returns: service status, Web3 connection status, cache size
    """
    is_connected = w3.is_connected()
    
    return {
        "status": "healthy" if is_connected else "unhealthy",
        "service": "blockchain-proxy",
        "web3_connected": is_connected,
        "provider": RPC_PROVIDER,
        "timestamp": datetime.now().isoformat(),
        "cache_stats": cache.stats()
    }

@app.post("/rpc", response_model=RPCResponse)
async def proxy_rpc(
    rpc_request: RPCRequest,
    x_tenant_id: Optional[str] = Header(None)
):

    """
    Main proxy endpoint - forwards JSON-RPC requests to blockchain
    
    Flow:
    1. Validate tenant
    2. Check cache
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
    
    #Check cache
    cached_result = cache.get(method, params)
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
        
        # Cache if applicable
        cache.set(method, params, result)
        if cache.get(method, params) is not None:
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
@app.on_event("startup")
async def startup_event():
    """Verify Web3 connection on startup"""
    if w3.is_connected():
        print(f"Connected to Ethereum via {RPC_PROVIDER}")
        print(f"Chain ID: {w3.eth.chain_id}")
        print(f"Latest Block: {w3.eth.block_number}")
    else:
        print(f"Failed to connect to {RPC_PROVIDER}")
        print(f"Check your API key in .env file")

if __name__ == '__main__':
    import uvicorn
    port = int(os.getenv('PORT', '8000'))
    uvicorn.run(app, host='0.0.0.0', port=port)

    