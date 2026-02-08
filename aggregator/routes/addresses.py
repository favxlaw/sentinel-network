from fastapi import APIRouter, Depends, HTTPException, status
import logging
import os
import re
import yaml

# Import custom modules
from auth import get_current_tenant
from models import AddAddressRequest, AddressAddedResponse, ErrorResponse
from config import get_config

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

    # Basic address validation
    if not re.fullmatch(r"0x[a-fA-F0-9]{40}", address):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid Ethereum address format"
        )

    logger.info(f"Adding address {address} for tenant {tenant_id}")

    config = get_config()
    tenant_path = config.tenant_config_path

    if not tenant_path or not os.path.exists(tenant_path):
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Tenant configuration file not found"
        )

    with open(tenant_path, "r") as f:
        data = yaml.safe_load(f) or {}

    tenants = data.get("tenants", {})
    if isinstance(tenants, list):
        # Convert list format to dict for update
        tenants_dict = {}
        for t in tenants:
            tid = t.get("id")
            if tid:
                tenants_dict[tid] = t
        tenants = tenants_dict

    if tenant_id not in tenants:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Tenant not found in configuration"
        )

    tenant_cfg = tenants[tenant_id]
    current = tenant_cfg.get("watch_addresses", [])
    current_lower = [a.lower() for a in current]

    if address in current_lower:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Address already being watched"
        )

    current.append(address)
    tenant_cfg["watch_addresses"] = current
    tenants[tenant_id] = tenant_cfg
    data["tenants"] = tenants

    # Persist config
    with open(tenant_path, "w") as f:
        yaml.safe_dump(data, f, sort_keys=False)

    return AddressAddedResponse(
        status="success",
        message=f"Added address {address} to watch list",
        tenant_id=tenant_id,
        address=address,
        note="Watcher service must be restarted or reloaded to pick up changes"
    )
