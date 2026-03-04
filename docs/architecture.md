# Sentinel Network Architecture

## 1. Architecture Overview

Sentinel Network is a multi-tenant Web3 monitoring platform that tracks on-chain activity for three tenants:
- `dao-alpha`
- `dao-beta`
- `dao-gamma`

The platform is deployed in AWS `us-east-1` (single AZ) and optimized for low cost:
- Terraform-managed infrastructure
- Single VPC with public/private subnet split
- NAT instance (`t2.micro`) instead of NAT Gateway
- Single backend EC2 instance in private subnet running all core services

Core functions:
- Poll blockchain activity
- Detect tenant-specific events
- Store events in tenant-partitioned SQLite tables
- Archive significant events to IPFS
- Serve tenant-scoped APIs behind NGINX gateway with per-tenant rate limits

## 2. Network Diagram (ASCII)

```text
AWS Region: us-east-1 (single AZ)
VPC: 10.0.0.0/16

                         Internet
                            |
                    +----------------+
                    | Internet GW    |
                    +----------------+
                            |
         ------------------------------------------------
         |                                              |
  Public Subnet (10.0.1.0/24)                   Private Subnet (10.0.10.0/24)
         |                                              |
  +-------------------+                                 |
  | Bastion (public)  |  SSH jump host                 |
  +-------------------+                                 |
  +-------------------+                                 |
  | NGINX (public)    | 443/80                          |
  | subdomain routing |---------------------------------+--> Backend (private)
  +-------------------+    proxy to :8006              |    +------------------------+
  +-------------------+                                 |    | Aggregator API :8006   |
  | NAT instance      |<--------------------------------+    | Blockchain Proxy :8545 |
  | source/dest off   | outbound for backend                 | Watcher service         |
  +-------------------+                                       | IPFS (Kubo) :5001      |
                                                              | SQLite + tenant tables |
                                                              +------------------------+
```

## 3. Data Flow

### Blockchain Event to Tenant API Response
1. `Watcher` polls Sepolia blocks continuously (every block cadence).
2. For each new block, watcher filters transactions against each tenant’s `watch_addresses`.
3. Matching events are written to tenant-partitioned SQLite tables (for example, `events_dao_alpha`).
4. If event value crosses tenant threshold, watcher posts receipt JSON to local IPFS and stores returned CID.
5. `Aggregator API` serves tenant-scoped endpoints (`/api/v1/events`, `/api/v1/events/{txhash}`, `/api/v1/receipt/{cid}`, `/api/v1/addresses`).
6. Public clients call tenant subdomains via NGINX:
   - `alpha.sentinel.local`
   - `beta.sentinel.local`
   - `gamma.sentinel.local`
7. NGINX applies per-tenant rate limits and forwards requests to backend aggregator (`10.0.10.20:8006`) with tenant context headers.
8. Aggregator authenticates using `X-Tenant-Key` and returns only tenant-authorized data.

## 4. Tenant Isolation

Isolation is enforced at multiple layers:

### Network Isolation
- Backend is private-only (no public IP).
- Bastion is the only SSH ingress path to private resources.
- Per-tenant security groups are provisioned via Terraform (`for_each` on `var.tenant_ids`).
- NGINX is the controlled ingress to tenant APIs.

### Application Isolation
- Tenant authentication through `X-Tenant-Key`.
- API handlers resolve tenant identity and scope all reads/writes by tenant.
- IPFS receipt access enforces tenant ownership checks (returns not found for cross-tenant access).

### Data Isolation
- SQLite events are tenant-partitioned by table.
- S3 event archival uses tenant prefixes:
  - `/{tenant-id}/YYYY/MM/DD/`

### Traffic Isolation
- Subdomain routing maps tenant traffic lanes independently.
- Per-tenant NGINX rate limits prevent one tenant from degrading others.

## 5. Security Design Decisions

### Access Control
- Least-privilege IAM roles for EC2 services (no hardcoded static credentials).
- Bastion-only SSH model to reduce direct attack surface.
- Private subnet for backend service stack.

### Network Security
- VPC segmentation (`public` vs `private` subnet).
- NAT instance for controlled outbound access from private subnet.
- Security-group-to-security-group rules for service communication.

### Service Hardening
- IPFS runs in private network mode:
  - `swarm.key` configured
  - `LIBP2P_FORCE_PNET=1`
  - public bootstrap peers removed
  - API/Gateway bound to localhost
- NGINX terminates TLS (wildcard self-signed cert for lab domain).

### Observability and Detection
- CloudWatch agent on instances for system and application logs.
- VPC Flow Logs for network-level auditability.
- Key log groups:
  - `/sentinel/tenant/{id}/events`
  - `/sentinel/system/nginx`
- Alarms:
  - watcher silent for >10 minutes
  - tenant rate-limit pressure (>80%)
  - IPFS unhealthy

### Data Protection and Retention
- S3 events bucket uses tenant-scoped prefix organization.
- Lifecycle transitions objects to Glacier after 30 days.
