# Sentinel Network

A production-ready AWS infrastructure and multi-tenant blockchain monitoring system for DAOs to track on-chain activity with data isolation and Web3 integration.

## Project Overview

Sentinel Network is a comprehensive solution combining:
- **Infrastructure as Code**: Complete AWS deployment via Terraform
- **Blockchain Monitoring**: Real-time event polling from Ethereum
- **Distributed Storage**: IPFS integration for event archival
- **Multi-tenant API**: FastAPI service with tenant isolation

## Key Features

- **Tenant Isolation**: API key-based access control per tenant
- **Event Streaming**: Real-time blockchain event detection
- **IPFS Storage**: Distributed archival of blockchain data
- **CloudWatch Monitoring**: Comprehensive logging and metrics
- **Cost Optimized**: Single AZ design with right-sized instances
- **Security Hardened**: Defense-in-depth security groups and IAM roles

## Architecture Highlights

**Network**
- VPC: 10.0.0.0/16
- Public Subnet: 10.0.1.0/24 (Bastion, NAT, NGINX)
- Private Subnet: 10.0.10.0/24 (Services, IPFS)

**Services**
- Bastion: SSH gateway
- IPFS Node: t3.medium with 100GB data volume
- Aggregator API: Multi-tenant service
- Blockchain Proxy: RPC caching layer
- Watcher: Event polling

## Quick Start

### Infrastructure Deployment

```bash
cd infra/
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

### Verify Installation

```bash
# Get infrastructure outputs
terraform output

# SSH to IPFS via bastion
ssh -i key.pem -J ubuntu@<bastion_ip> ubuntu@<ipfs_ip>
systemctl status ipfs
```

## Components
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

