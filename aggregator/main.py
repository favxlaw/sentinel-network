import logging
from datetime import datetime
from fastapi import FastAPI, Request, status
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

# Import our custom modules
from config import get_config, settings
from models import ErrorResponse

# Import route modules (we'll create these next)
from routes import events, receipts, addresses, health



def setup_logging():
    log_level = settings.log_level
    
    logging.basicConfig(
        level=getattr(logging, log_level),
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    
    # Create logger for this module
    logger = logging.getLogger(__name__)
    logger.info(f"Logging configured at {log_level} level")
    
    return logger

logger = setup_logging()

app = FastAPI(
    title="Sentinel Network Aggregator API",
)


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify exact domains
    allow_credentials=True,
    allow_methods=["*"],  # GET, POST, PUT, DELETE, etc.
    allow_headers=["*"],  # All headers including X-Tenant-Key
)


@app.middleware("http")
async def log_requests(request: Request, call_next):
    start_time = datetime.now()
    
    # Process the request
    response = await call_next(request)
    
    # Calculate how long it took
    duration = (datetime.now() - start_time).total_seconds()
    
    # Log the request
    logger.info(
        f"{request.method} {request.url.path} - "
        f"Completed in {duration:.3f}s with status {response.status_code}"
    )
    
    return response


# Include all route modules
app.include_router(health.router, tags=["Health"])
app.include_router(events.router, tags=["Events"])
app.include_router(receipts.router, tags=["Receipts"])
app.include_router(addresses.router, tags=["Addresses"])

logger.info("All route modules loaded")

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    """
    Handle validation errors from Pydantic models.
    
    When this happens:
    - User sends invalid data (e.g., address missing 0x prefix)
    - Pydantic validation fails
    - This handler catches it and returns nice error
    
    Example:
    User sends: {"address": "not-an-address"}
    Pydantic raises: RequestValidationError
    We return: {"error": "Address must start with 0x", "status_code": 400}
    """
    logger.warning(f"Validation error: {exc}")
    
    return JSONResponse(
        status_code=status.HTTP_400_BAD_REQUEST,
        content={
            "error": "Validation error",
            "detail": str(exc),
            "status_code": 400,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
    )


@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "error": "Internal server error",
            "detail": "An unexpected error occurred. Please try again later.",
            "status_code": 500,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
    )

@app.on_event("startup")
async def startup_event():
    logger.info("=" * 60)
    logger.info("Starting Sentinel Network Aggregator API")
    logger.info("=" * 60)
    
    # Validate configuration
    if not settings.validate():
        logger.error("Configuration validation failed!")
        logger.error("Please fix configuration and restart")
        # In production, I might want to exit here:
        # import sys; sys.exit(1)
    
    logger.info(f"Environment: {settings.environment}")
    logger.info(f"Database: {settings.db_path}")
    logger.info(f"Loaded {len(settings.tenants)} tenants")
    
    # Log tenant IDs (but NOT API keys!)
    tenant_ids = list(settings.tenants.keys())
    logger.info(f"Tenants: {', '.join(tenant_ids)}")
    
    # Check database
    import os
    if os.path.exists(settings.db_path):
        logger.info("Database found")
    else:
        logger.warning("Database not found yet - Watcher service will create it")
    
    logger.info("=" * 60)
    logger.info("API server ready to accept connections")
    logger.info("=" * 60)


@app.on_event("shutdown")
async def shutdown_event():
    logger.info("Shutting down Sentinel Network Aggregator API")
    logger.info("Goodbye!")



@app.get("/")
async def root():
    
    return {
        "service": "Sentinel Network Aggregator API", 
        "endpoints":
             {
            "health": "/health",
            "events": "/api/v1/events",
            "receipts": "/api/v1/receipt/{cid}",
            "addresses": "/api/v1/addresses",
            "stats": "/api/v1/stats"
        }
    }


if __name__ == "__main__":
    logger.info("Starting development server...")
    logger.info(f"API docs available at: http://{settings.api_host}:{settings.api_port}/docs")
    
    uvicorn.run(
        app,
        host=settings.api_host,
        port=settings.api_port,
        log_level=settings.log_level.lower(),
        access_log=True
    )