"""
routes/receipts.py - Receipt Information Endpoints

Returns receipt information (CID and event details) for significant events.
The actual IPFS retrieval is handled by the client or IPFS node directly.
"""

from fastapi import APIRouter, Depends, HTTPException, status
import logging

# Import custom modules
from auth import get_current_tenant
from database import get_event_by_hash, DatabaseError
from models import EventResponse, ErrorResponse

logger = logging.getLogger(__name__)

# Create router
router = APIRouter()


@router.get(
    "/api/v1/receipt/{tx_hash}",
    response_model=EventResponse,
    summary="Retrieve event receipt (CID) from database",
    description="""
    Fetch a stored event receipt using its transaction hash.
    
    If the event has an IPFS CID, it's included in the response.
    Only receipts for your tenant's events can be retrieved.
    
    ## Parameters
    - **tx_hash**: Transaction hash (0x...)
    
    ## Response
    Returns the event with IPFS CID if this was a significant event.
    
    The CID can then be used to retrieve the full receipt from IPFS if needed.
    
    ## Example
    ```
    curl -H "X-Tenant-Key: your-api-key" \\
      http://api.sentinel.local/api/v1/receipt/0xabc123def456...
    ```
    """,
    responses={
        200: {"description": "Receipt found and returned"},
        401: {"description": "Unauthorized - invalid API key", "model": ErrorResponse},
        404: {"description": "Receipt not found", "model": ErrorResponse},
        500: {"description": "Server error", "model": ErrorResponse}
    }
)
def get_receipt(
    tx_hash: str,
    tenant_id: str = Depends(get_current_tenant)
) -> EventResponse:
    """
    Retrieve event receipt from database.
    
    Args:
        tx_hash: Transaction hash
        tenant_id: Authenticated tenant (from X-Tenant-Key header)
    
    Returns:
        EventResponse with event details and IPFS CID if available
    
    Raises:
        404: If event not found in database
        500: If database error occurs
    """
    
    try:
        # Get event from database
        event = get_event_by_hash(tenant_id, tx_hash)
        
        if not event:
            logger.warning(f"Receipt not found for tx_hash: {tx_hash}, tenant: {tenant_id}")
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Receipt with tx_hash {tx_hash} not found"
            )
        
        logger.info(f"Retrieved receipt {tx_hash} for tenant {tenant_id}")
        return EventResponse(**event)
    
    except DatabaseError as e:
        logger.error(f"Database error retrieving receipt {tx_hash}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve receipt from database"
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Unexpected error retrieving receipt {tx_hash}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve receipt"
        )
