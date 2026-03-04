import logging
from typing import Any, Dict

from fastapi import APIRouter, Depends, HTTPException, status

from auth import get_current_tenant
from ipfs_client import IPFSClient
from models import ErrorResponse

logger = logging.getLogger(__name__)
router = APIRouter()
ipfs_client = IPFSClient()


@router.get(
    "/api/v1/receipt/{cid}",
    response_model=Dict[str, Any],
    summary="Fetch receipt content from IPFS",
    responses={
        200: {"description": "Receipt content returned"},
        401: {"description": "Unauthorized - invalid API key", "model": ErrorResponse},
        404: {"description": "Receipt not found", "model": ErrorResponse},
        500: {"description": "Server error", "model": ErrorResponse},
    },
)
def get_receipt(
    cid: str,
    tenant_id: str = Depends(get_current_tenant),
) -> Dict[str, Any]:
    try:
        receipt = ipfs_client.get_json(cid)
        if not receipt:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Receipt with CID {cid} not found",
            )

        payload_tenant = receipt.get("tenant_id") if isinstance(receipt, dict) else None
        if payload_tenant and payload_tenant != tenant_id:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Receipt with CID {cid} not found",
            )

        return receipt
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("Unexpected error retrieving CID %s: %s", cid, exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve receipt",
        )
