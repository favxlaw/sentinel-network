from pydantic import BaseModel, Field, field_validator, validator
from typing import Optional, List
from datetime import datetime

class EventResponse(BaseModel):
    """
    Event response model for API responses.
    """
    tx_hash: str = Field(
        ...,
        description="Transaction hash (unique identifier)",
        example="0xabc123def456..."
    )
    
    from_address: str = Field(
        ...,
        description="Sender's Ethereum address",
        example="0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb"
    )
    
    to_address: str = Field(
        ...,
        description="Receiver's Ethereum address",
        example="0x1234567890abcdef1234567890abcdef12345678"
    )
    
    value_eth: str = Field(
        ...,
        description="Transaction value in ETH (as string to preserve precision)",
        example="15.5"
    )
    
    block_number: int = Field(
        ...,
        description="Block number where transaction was mined",
        example=12345678
    )
    
    timestamp: str = Field(
        ...,
        description="When the transaction occurred (ISO 8601 format)",
        example="2026-01-23T10:30:00"
    )
    
    ipfs_cid: Optional[str] = Field(
        None,  # None means it's optional (can be null)
        description="IPFS CID if this is a significant event (above threshold)",
        example="QmXk3v7w9abcdefghijklmnopqrstuvwxyz"
    )
    
    class Config:
        """
        Pydantic configuration for this model.
        
        orm_mode = True allows creating this model from database rows:
        
            db_row = {"tx_hash": "0xabc", "value_eth": "10.5", ...}
            event = EventResponse(**db_row)  # Works!
        
        This is super useful because our database returns dictionaries,
        and Pydantic can automatically convert them to EventResponse objects.
        """
        orm_mode = True


class AddAddressRequest(BaseModel):
    """Request model for adding a new address to watch"""
    address: str = Field(
        description="Ethereum address to monitor (must start with 0x)",
        example="0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb",
        min_length=42,  # Ethereum addresses are exactly 42 characters
        max_length=42
    )

    @field_validator('address')
    def validate_ethereum_address(cls, v):
        if not v.startswith('0x'):
            raise ValueError('Address must start with 0x')
        if len(v) != 42:
            raise ValueError('Address must be exactly 42 characters (0x + 40 hex digits)')
        try:
            int(v[2:], 16)  # Try to parse as hexadecimal
        except ValueError:
            raise ValueError('Address must contain only valid hexadecimal characters')
        
        # Return lowercase version (Ethereum addresses are case-insensitive)
        return v.lower()


class ReceiptResponse(BaseModel):
    """
    Full event receipt from IPFS (more detailed than EventResponse).
    
    This includes extra blockchain data like gas used and gas price.
    Only available for significant events that were posted to IPFS.
    
    Example JSON:
    {
        "tx_hash": "0xabc123...",
        "from_address": "0x742d35...",
        "to_address": "0x123456...",
        "value_eth": "15.5",
        "block_number": 12345678,
        "timestamp": "2026-01-23T10:30:00",
        "gas_used": 21000,
        "gas_price": "50.0",
        "ipfs_cid": "QmXk3v7w9..."
    }
    """
    
    # All the same fields as EventResponse
    tx_hash: str
    from_address: str
    to_address: str
    value_eth: str
    block_number: int
    timestamp: str
    
    # Additional fields only in IPFS receipts
    gas_used: Optional[int] = Field(
        None,
        description="Gas units consumed by transaction",
        example=21000
    )
    
    gas_price: Optional[str] = Field(
        None,
        description="Gas price in Gwei (as string)",
        example="50.0"
    )
    
    ipfs_cid: str = Field(
        ...,
        description="The IPFS CID of this receipt"
    )
    
    class Config:
        orm_mode = True


class AddressAddedResponse(BaseModel):
    status: str = Field(..., example="success")
    message: str
    tenant_id: str
    address: str
    note: Optional[str] = None


class TenantStatsResponse(BaseModel):
    """
    Statistics about a tenant's monitoring activity.
    
    Example JSON:
    {
        "tenant_id": "dao-alpha",
        "total_events": 1523,
        "significant_events": 47,
        "normal_events": 1476,
        "latest_event": "2026-01-23T10:15:00",
        "watched_addresses": 3,
        "alert_threshold_eth": 10.0
    }
    """
    
    tenant_id: str
    total_events: int = Field(..., description="Total number of events detected")
    significant_events: int = Field(..., description="Events above threshold (in IPFS)")
    normal_events: int = Field(..., description="Events below threshold")
    latest_event: Optional[str] = Field(None, description="Timestamp of most recent event")
    watched_addresses: int = Field(..., description="Number of addresses being monitored")
    alert_threshold_eth: float = Field(..., description="Threshold for IPFS storage")


class HealthCheckResponse(BaseModel):
    """
    Health check response (used by load balancers to check if service is alive).
    
    Example JSON:
    {
        "status": "healthy",
        "service": "aggregator-api",
        "timestamp": "2026-01-23T10:30:00",
        "ipfs_status": "online",
        "tenants_loaded": 3
    }
    """
    
    status: str = Field(..., example="healthy")
    service: str = Field(..., example="aggregator-api")
    timestamp: str = Field(..., description="Current server time")
    ipfs_status: str = Field(..., example="online", description="IPFS node status")
    tenants_loaded: int = Field(..., description="Number of tenants configured")


class ErrorResponse(BaseModel):
    error: str = Field(..., description="Error message")
    status_code: int = Field(..., description="HTTP status code")
    timestamp: str = Field(..., description="When the error occurred")
    detail: Optional[str] = Field(None, description="Additional error details")

class EventListResponse(BaseModel):
    """
    Wrapper for list of events with metadata.
    
    Instead of returning just a list:
    [event1, event2, event3]
    
    We return:
    {
        "events": [event1, event2, event3],
        "count": 3,
        "tenant_id": "dao-alpha"
    }
    
    This gives clients more context.
    """
    
    events: List[EventResponse]
    count: int = Field(..., description="Number of events in this response")
    tenant_id: str = Field(..., description="Which tenant these events belong to")
    limit: int = Field(..., description="Maximum events returned (from query parameter)")

def event_from_db_row(row: dict) -> EventResponse:
    """
    Convert database row to EventResponse object.
    
    Why this helper?
    - Database returns plain dictionaries
    - We want Pydantic models for validation and type safety
    - This function bridges the gap
    
    Args:
        row: Dictionary from database (e.g., {"tx_hash": "0xabc", ...})
    
    Returns:
        Validated EventResponse object
    
    Example:
        db_row = database.get_event("0xabc123")
        event = event_from_db_row(db_row)
        # Now 'event' has all Pydantic validation and type safety
    """

    return EventResponse(**row)

def events_from_db_rows(rows: List[dict]) -> List[EventResponse]:
    """
    Convert multiple database rows to EventResponse objects.
    
    Args:
        rows: List of dictionaries from database
    
    Returns:
        List of validated EventResponse objects
    
    Example:
        db_rows = database.get_all_events("dao-alpha")
        events = events_from_db_rows(db_rows)
    """
    return [event_from_db_row(row) for row in rows]