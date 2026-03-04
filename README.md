# Sentinel Network

A multi-tenant blockchain monitoring system for DAOs to track on-chain activity securely and in isolation.

## What It Does

Sentinel Network monitors Ethereum blockchain addresses and streams events to multiple tenants, each seeing only their own data. Built for Web3 infrastructure with cost-efficiency in mind.

## Components

- **Watcher Service**: Polls Ethereum via Alchemy, detects transactions, stores events in SQLite
- **Aggregator API**: FastAPI service with tenant authentication - each tenant queries only their data
- **Blockchain Proxy**: RPC request caching layer (memory/Redis backends)
- **IPFS Integration**: Archives significant events to distributed storage

## What's Implemented

✅ **Core Architecture**
- Tenant isolation via API keys (X-Tenant-Key header)
- SQLite database with per-tenant tables
- Alchemy RPC integration (Sepolia testnet)
- Blockchain polling with catch-up logic

✅ **API Features**
- `/health` - Service health check
- `/api/v1/events` - Get tenant events with pagination
- `/api/v1/events/{tx_hash}` - Event details
- `/api/v1/addresses` - Add addresses to watch
- Comprehensive error handling & logging

✅ **Infrastructure**
- In-memory caching (5min TTL) - Redis ready for prod
- Multi-tenant request logging
- Configuration via YAML + environment variables
- Systemd-ready services

## Quick Start

```bash
# Install dependencies
pip install -r watcher-service/requirements.txt
pip install -r aggregator/requirements.txt

# Set up environment
cp aggregator/.env.example aggregator/.env
cp watcher-service/.env.example watcher-service/.env

# Start services
python3 watcher-service/watcher.py &
uvicorn aggregator.main:app --port 8006

# Test API
curl -H "X-Tenant-Key: alpha-secret-key-123" http://localhost:8006/api/v1/events
```

## Configuration

### Tenants (watcher-service/config/tenants.yaml)
```yaml
tenants:
  dao-alpha:
    api_key: alpha-secret-key-123
    watch_addresses: [0x...]
    alert_threshold_eth: 10.0
```

### Environment Variables
- `ALCHEMY_API_KEY` - RPC endpoint key
- `IPFS_API_URL` - IPFS node endpoint
- `SENTINEL_DB_PATH` - Database location
- `LOG_LEVEL` - Logging verbosity

## Testing

```bash
# Health check (no auth required)
curl http://localhost:8006/health

# Query with tenant key
curl -H "X-Tenant-Key: alpha-secret-key-123" \
  http://localhost:8006/api/v1/events

# Test auth failure
curl -H "X-Tenant-Key: invalid" \
  http://localhost:8006/api/v1/events  # Returns 401
```

## Architecture

```
Ethereum → Alchemy RPC → Watcher → SQLite DB → Aggregator API → Tenant
                           ↓
                         IPFS (significant events)
```

## Git Workflow

- `main` - Protected branch (production ready)
- Feature branches: `feature/watcher-ipfs-integration`
- Conventional commits: `feat:`, `fix:`, `docs:`

## Next Steps

- [ ] Deploy to AWS (VPC, EC2, RDS)
- [ ] Redis for production caching
- [ ] NGINX gateway with subdomain routing
- [ ] CloudWatch monitoring & alarms
- [ ] Multi-chain support
