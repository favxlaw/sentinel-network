from fastapi import APIRouter
from models import HealthCheckResponse
from datetime import datetime
import logging

logger = logging.getLogger(__name__)

# Create router
router = APIRouter()


@router.get(
    "/health",
    response_model=HealthCheckResponse,
    summary="Health check endpoint",
    responses={
        200: {"description": "Service is healthy"}
    }
)
def health_check() -> HealthCheckResponse:
    return HealthCheckResponse(
        status="healthy",
        service="aggregator-api",
        timestamp=datetime.now().isoformat(),
        ipfs_status="online",  # TODO: Check actual IPFS connection
        tenants_loaded=3  # TODO: Load from config
    )
