from fastapi import APIRouter, Depends, Query, HTTPException, status
from typing import List
import logging

# Import our custom modules
from auth import get_current_tenant
from database import (
    get_tenant_events,
    get_event_by_hash,
    get_tenant_stats,
    get_events_by_address,
    get_significant_events,
    DatabaseError
)
from models import (
    EventResponse,
    TenantStatsResponse,
    ErrorResponse
)
from config import get_config

# Create logger for this module
logger = logging.getLogger(__name__)

# Create router
# This router will be included in main.py
router = APIRouter()


@router.get(
    "/api/v1/events",
    response_model=List[EventResponse],
    summary="Get all events for your tenant",
    responses={
        200: {"description": "Success - returns list of events"},
        401: {"description": "Unauthorized - invalid or missing API key", "model": ErrorResponse},
        500: {"description": "Server error", "model": ErrorResponse}
    }
)
async def get_events(
    tenant_id: str = Depends(get_current_tenant),
    limit: int = Query(100, ge=1, le=1000, description="Maximum events to return"),
    offset: int = Query(0, ge=0, description="Number of events to skip")
):
    try:
        logger.info(f"Fetching events for {tenant_id}, limit={limit}, offset={offset}")
        
        # Query database
        events = get_tenant_events(tenant_id, limit=limit, offset=offset)
        
        logger.info(f"Returning {len(events)} events for {tenant_id}")
        
        # FastAPI automatically converts dict to EventResponse (validates format)
        return events
        
    except DatabaseError as e:
        logger.error(f"Database error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve events from database"
        )


@router.get(
    "/api/v1/events/{tx_hash}",
    response_model=EventResponse,
    summary="Get specific event by transaction hash",
    responses={
        200: {"description": "Success - returns event details"},
        401: {"description": "Unauthorized"},
        404: {"description": "Event not found or doesn't belong to your tenant"},
        500: {"description": "Server error"}
    }
)
async def get_event(
    tx_hash: str,
    tenant_id: str = Depends(get_current_tenant)
):
    try:
        logger.info(f"Fetching event {tx_hash} for {tenant_id}")
        
        # Query database for this specific event
        event = get_event_by_hash(tenant_id, tx_hash)
        
        if not event:
            logger.warning(f"Event {tx_hash} not found for {tenant_id}")
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Event {tx_hash} not found for your tenant"
            )
        
        logger.info(f"Found event {tx_hash} for {tenant_id}")
        return event
        
    except DatabaseError as e:
        logger.error(f"Database error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve event"
        )


@router.get(
    "/api/v1/stats",
    response_model=TenantStatsResponse,
    summary="Get statistics for your tenant",
)
async def get_stats(tenant_id: str = Depends(get_current_tenant)):
    """
    Get statistics for tenant.
    
    Returns:
        TenantStatsResponse with all statistics
    """
    try:
        logger.info(f"Fetching stats for {tenant_id}")
        
        # Get stats from database
        stats = get_tenant_stats(tenant_id)
        
        # Get tenant configuration
        config = get_config()
        tenant_config = config.get_tenant(tenant_id)
        
        # Build response
        response = TenantStatsResponse(
            tenant_id=tenant_id,
            total_events=stats['total_events'],
            significant_events=stats['significant_events'],
            normal_events=stats['normal_events'],
            latest_event=stats['latest_event'],
            watched_addresses=len(tenant_config.get('watch_addresses', [])),
            alert_threshold_eth=tenant_config.get('alert_threshold_eth', 0)
        )
        
        logger.info(f"Returning stats for {tenant_id}: {stats['total_events']} total events")
        return response
        
    except DatabaseError as e:
        logger.error(f"Database error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve statistics"
        )


@router.get(
    "/api/v1/events/by-address/{address}",
    response_model=List[EventResponse],
    summary="Get events for specific address",
    description="Returns events where the address is sender OR receiver"
)
async def get_events_for_address(
    address: str,
    tenant_id: str = Depends(get_current_tenant),
    limit: int = Query(100, ge=1, le=1000)
):
    """
    Get all events involving a specific address.
    
    Useful for tracking activity of a single address.
    
    Args:
        address: Ethereum address to filter by
        tenant_id: From authentication
        limit: Maximum results
    
    Returns:
        List of events where address is sender or receiver
    """
    try:
        logger.info(f"Fetching events for address {address}, tenant {tenant_id}")
        
        # Validate address format
        if not address.startswith('0x') or len(address) != 42:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid Ethereum address format"
            )
        
        events = get_events_by_address(tenant_id, address, limit=limit)
        
        logger.info(f"Found {len(events)} events for address {address}")
        return events
        
    except DatabaseError as e:
        logger.error(f"Database error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve events"
        )


@router.get(
    "/api/v1/events/significant",
    response_model=List[EventResponse],
    summary="Get only significant events",
    description="Returns events above threshold that were stored in IPFS"
)
async def get_significant_events_endpoint(
    tenant_id: str = Depends(get_current_tenant),
    limit: int = Query(100, ge=1, le=1000)
):
    try:
        logger.info(f"Fetching significant events for {tenant_id}")
        
        events = get_significant_events(tenant_id, limit=limit)
        
        logger.info(f"Found {len(events)} significant events for {tenant_id}")
        return events
        
    except DatabaseError as e:
        logger.error(f"Database error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve significant events"
        )