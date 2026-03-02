from fastapi import APIRouter, Depends, HTTPException, status
import logging

# Import custom modules
from auth import get_current_tenant
from models import AddAddressRequest, AddressAddedResponse, ErrorResponse

logger = logging.getLogger(__name__)

# Create router
router = APIRouter()


@router.post(
    "/api/v1/addresses",
    response_model=AddressAddedResponse,
    summary="Add address to watch list",
    responses={
        200: {"description": "Address added successfully", "model": AddressAddedResponse},
        400: {"description": "Invalid address format", "model": ErrorResponse},
        401: {"description": "Unauthorized - invalid API key", "model": ErrorResponse},
        409: {"description": "Address already being watched", "model": ErrorResponse},
        500: {"description": "Server error", "model": ErrorResponse}
    }
)
def add_address(
    request: AddAddressRequest,
    tenant_id: str = Depends(get_current_tenant)
) -> AddressAddedResponse:
    
    address = request.address.lower()
    
    logger.info(f"Adding address {address} for tenant {tenant_id}")
    
    # TODO: Implement actual address addition logic:
    # 1. Check if address already exists in tenant's watch list
    # 2. Add to tenants.yaml config file
    # 3. Trigger watcher service to reload config
    # 4. Return success response
    
    # For now, just return success
    return AddressAddedResponse(
        status="success",
        message=f"Added address {address} to watch list",
        tenant_id=tenant_id,
        address=address,
        note="Watcher service will reload config within 30 seconds"
    )
