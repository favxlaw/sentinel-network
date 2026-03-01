# Sentinel Network Architecture

## Overview
Sentinel Network is a multi-tenant blockchain monitoring system with strict tenant isolation at the API layer. It runs a single backend instance (proxy + watcher + IPFS + aggregator) behind a public NGINX gateway, with private subnet isolation and a NAT instance for outbound internet access.

## Data Flow
1. Watcher polls the blockchain through the local blockchain proxy.
2. The proxy caches requests and forwards to Alchemy/Infura (Sepolia).
3. Watcher writes events to a tenant-partitioned SQLite database.
4. Significant events are stored to IPFS and the CID is recorded.
5. Aggregator exposes tenant-scoped API endpoints.
6. NGINX routes subdomains to the aggregator and enforces per-tenant rate limits.

## Network Layout
- VPC: `10.0.0.0/16`
- Public subnet: `10.0.1.0/24`
  - Internet Gateway
  - NAT instance
  - Bastion host
  - NGINX gateway
- Private subnet: `10.0.10.0/24`
  - Backend instance (proxy, watcher, IPFS, aggregator)

## Tenant Isolation
- Per-tenant API keys in `config/tenants.yaml` and environment variables.
- Aggregator enforces tenant-scoped access with `X-Tenant-Key`.
- NGINX rate limits per tenant subdomain.
- SQLite tables are partitioned by tenant ID.

## Observability
- VPC Flow Logs to CloudWatch.
- CloudWatch agent for system logs and NGINX logs.
- Application logs are written to service log directories and systemd journal.
