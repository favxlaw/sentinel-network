import logging
import os
import threading

import yaml
from fastapi import APIRouter, Depends, HTTPException, status

from auth import get_current_tenant
from config import get_config
from models import AddAddressRequest, AddressAddedResponse, ErrorResponse

logger = logging.getLogger(__name__)
router = APIRouter()

TENANT_CONFIG_LOCK = threading.Lock()


def _validate_eth_address(address: str) -> str:
    normalized = address.lower()
    if not normalized.startswith("0x") or len(normalized) != 42:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid Ethereum address format"
        )
    try:
        int(normalized[2:], 16)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid Ethereum address format"
        )
    return normalized


@router.post(
    "/api/v1/addresses",
    response_model=AddressAddedResponse,
    summary="Add address to watch list",
    responses={
        200: {"description": "Address added successfully", "model": AddressAddedResponse},
        400: {"description": "Invalid address format", "model": ErrorResponse},
        401: {"description": "Unauthorized - invalid API key", "model": ErrorResponse},
        409: {"description": "Address already being watched", "model": ErrorResponse},
        500: {"description": "Server error", "model": ErrorResponse},
    },
)
def add_address(
    request: AddAddressRequest,
    tenant_id: str = Depends(get_current_tenant),
) -> AddressAddedResponse:
    address = _validate_eth_address(request.address)
    config = get_config()
    tenant_config_path = os.getenv("TENANT_CONFIG", config.tenant_config_path)

    with TENANT_CONFIG_LOCK:
        try:
            with open(tenant_config_path, "r", encoding="utf-8") as file:
                config_data = yaml.safe_load(file) or {}
        except FileNotFoundError:
            logger.error("Tenant config file not found: %s", tenant_config_path)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Tenant configuration file not found",
            )
        except yaml.YAMLError as exc:
            logger.error("Invalid tenant config YAML: %s", exc)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Tenant configuration format is invalid",
            )

        tenants = config_data.get("tenants")
        tenant_entry = None

        if isinstance(tenants, list):
            for item in tenants:
                if isinstance(item, dict) and item.get("id") == tenant_id:
                    tenant_entry = item
                    break
        elif isinstance(tenants, dict):
            tenant_entry = tenants.get(tenant_id)
            if isinstance(tenant_entry, dict) and "id" not in tenant_entry:
                tenant_entry["id"] = tenant_id
        else:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Tenant configuration format is invalid",
            )

        if not isinstance(tenant_entry, dict):
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Tenant configuration not found",
            )

        watch_addresses = tenant_entry.get("watch_addresses")
        if watch_addresses is None:
            watch_addresses = []
            tenant_entry["watch_addresses"] = watch_addresses
        if not isinstance(watch_addresses, list):
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="watch_addresses must be a list",
            )

        existing = {str(addr).lower() for addr in watch_addresses}
        if address in existing:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Address already being watched",
            )

        watch_addresses.append(address)

        try:
            with open(tenant_config_path, "w", encoding="utf-8") as file:
                yaml.safe_dump(config_data, file, sort_keys=False)
        except OSError as exc:
            logger.error("Failed writing tenant config %s: %s", tenant_config_path, exc)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to persist tenant configuration",
            )

    config.reload_tenants()

    return AddressAddedResponse(
        status="success",
        message=f"Added address {address} to watch list",
        tenant_id=tenant_id,
        address=address,
        note="Watcher will pick up new address within one poll interval",
    )
