from fastapi import Header, HTTPException, status
from typing import Optional
import logging
from config import get_config

from config import get_config
logger = logging.getLogger(__name__)

class AuthenticationError(Exception):
    pass

def get_tenant_from_key(tenant_key: Optional[str]) -> str:
    if not tenant_key:
        logger.warning("Authentication failed: Missing X-Tenant-Key header")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing X-Tenant-Key header. Please provide your API key.",
            headers={"WWW-Authenticate": "ApiKey"} 
        )

    config = get_config()
    tenant_id = config.get_tenant_by_api_key(tenant_key)

    if not tenant_id:
        # Log the failure (but only first 10 chars of key for security)
        logger.warning(f"Authentication failed: Invalid API key (starts with {tenant_key[:10]}...)")
        
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid API key. Please check your credentials.",
            headers={"WWW-Authenticate": "ApiKey"}
        )
    logger.info(f"Authentication successful: {tenant_id}")
    return tenant_id

def get_current_tenant(
    x_tenant_key: str = Header(
        ...,  #parameter is REQUIRED
        description="Your API key for authentication",
        example="alpha-secret-key-123"
    )
) -> str:
    return get_tenant_from_key(x_tenant_key)


def verify_tenant_access(tenant_id: str, resource_owner: str) -> None:
    if tenant_id != resource_owner:
        logger.warning(
            f"Authorization failed: {tenant_id} attempted to access "
            f"resource owned by {resource_owner}"
        )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You don't have permission to access this resource"
        )
    
def validate_api_key_format(api_key: str) -> bool:
    if len(api_key) < 20:
        logger.warning(f"API key too short: {len(api_key)} characters")
        return False
    
     # Check for default/example keys
    weak_patterns = [
        'CHANGE_THIS',
        'example',
        'test123',
        'secret',
        'password'
    ]

    api_key_lower = api_key.lower()
    for pattern in weak_patterns:
        if pattern in api_key_lower:
            logger.warning(f"API key contains weak pattern: {pattern}")
            return False
    
    return True

class RateLimiter:
    """
    Rate limiting to prevent abuse.
    
    FUTURE IMPLEMENTATION:
    Track requests per tenant and block if exceeding limit.
    
    Example config in tenants.yaml:
        rate_limit_per_minute: 100
    
    Usage:
        @rate_limit
        @app.get("/events")
        def get_events():
            pass
    
    For now, NGINX handles rate limiting, but we can add
    application-level rate limiting here if needed.
    """

def __init__(self):
     self.request_counts = {}
    
def check_rate_limit(self, tenant_id: str) -> bool:
    return True