# Sentinel Network Runbook

Operations runbook for common failures in Sentinel Network.

## Topology
- EC2: `nat` (public), `bastion` (public), `nginx` (public), `backend` (private)
- Backend services (systemd): `ipfs-node`, `blockchain-proxy`, `aggregator`, `watcher`
- Backend egress path: private subnet -> NAT instance -> Internet Gateway
- NGINX routes tenant subdomains to backend aggregator on port `8006`
- Tenants: `dao-alpha`, `dao-beta`, `dao-gamma`
- Infrastructure is managed with Terraform (`infra/`)

## 1) Backend instance not showing in SSM Session Manager

### Detect
```bash
aws ssm describe-instance-information --region us-east-1
```
If backend is missing, SSM registration is failing.

On backend (from bastion via SSH):
```bash
systemctl status snap.amazon-ssm-agent.amazon-ssm-agent --no-pager
journalctl -u snap.amazon-ssm-agent.amazon-ssm-agent -n 100 --no-pager
```

### Most likely cause
- SSM agent not running
- Missing IAM instance profile permissions (`AmazonSSMManagedInstanceCore`)
- Backend has no outbound internet via NAT

### Fix
On backend:
```bash
sudo systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent
sudo systemctl restart snap.amazon-ssm-agent.amazon-ssm-agent
```

Check IAM profile in Terraform/apply if missing:
```bash
cd infra
terraform plan
terraform apply
```

If outbound is broken, follow Scenario 6.

### Verify
```bash
aws ssm describe-instance-information --region us-east-1
```
Backend instance appears with `PingStatus: Online`.

## 2) Watcher service is silent (not processing blocks)

### Detect
On backend:
```bash
systemctl status watcher --no-pager
journalctl -u watcher -n 200 --no-pager
tail -n 100 /opt/sentinel/sentinel-network/watcher-service/logs/system.log
```
Look for missing `Processed block` / no new block activity.

### Most likely cause
- Watcher crashed or stuck
- RPC access failure to blockchain proxy / upstream provider
- Invalid tenant config (`watcher-service/config/tenants.yaml`)

### Fix
```bash
sudo systemctl restart blockchain-proxy
sudo systemctl restart watcher
```

Validate watcher config:
```bash
python3 - <<'PY'
import yaml
p=" /opt/sentinel/sentinel-network/watcher-service/config/tenants.yaml".strip()
print(yaml.safe_load(open(p)))
PY
```

Check proxy health:
```bash
curl -sS http://127.0.0.1:8545/health
```

### Verify
```bash
journalctl -u watcher -f
```
Confirm new block processing logs resume.

## 3) IPFS node is unhealthy

### Detect
```bash
systemctl status ipfs-node --no-pager
journalctl -u ipfs-node -n 200 --no-pager
curl -sS -X POST http://127.0.0.1:5001/api/v0/version
```

### Most likely cause
- `ipfs-node` service stopped
- IPFS repo misconfiguration under `/data/ipfs`
- Private-network config issue (`swarm.key`, `LIBP2P_FORCE_PNET`)

### Fix
```bash
sudo ls -l /data/ipfs/swarm.key
sudo chown sentinel:sentinel /data/ipfs/swarm.key
sudo chmod 600 /data/ipfs/swarm.key
sudo systemctl daemon-reload
sudo systemctl restart ipfs-node
```

If repo corrupted, re-run backend provisioning for IPFS setup.

### Verify
```bash
systemctl is-active ipfs-node
curl -sS -X POST http://127.0.0.1:5001/api/v0/version
```
Service is `active` and API responds with version JSON.

## 4) NGINX returning 502 Bad Gateway

### Detect
On nginx instance:
```bash
sudo systemctl status nginx --no-pager
sudo tail -n 100 /var/log/nginx/error.log
```

Check backend reachability from nginx:
```bash
curl -sS http://10.0.10.20:8006/health
```

### Most likely cause
- Aggregator service down on backend
- Wrong backend IP/port in generated NGINX tenant configs
- Security group path broken between nginx -> backend:8006

### Fix
On backend:
```bash
sudo systemctl status aggregator --no-pager
sudo systemctl restart aggregator
```

On nginx:
```bash
sudo nginx -t
sudo systemctl reload nginx
```

Re-apply Terraform if SGs or userdata changed:
```bash
cd infra
terraform apply
```

### Verify
```bash
curl -k https://alpha.sentinel.local/health
```
Should return healthy response, no 502.

## 5) NGINX returning 429 Too Many Requests unexpectedly

### Detect
```bash
sudo tail -n 200 /var/log/nginx/access.log | grep " 429 "
sudo tail -n 100 /var/log/nginx/error.log
```

### Most likely cause
- Tenant rate limit too low for traffic pattern
- Burst settings too strict
- Client retries/spikes

### Fix
Adjust `tenant_rate_limits` in `infra/terraform.tfvars`, then apply:
```bash
cd infra
terraform plan
terraform apply
```

Reload nginx if needed:
```bash
sudo nginx -t
sudo systemctl reload nginx
```

### Verify
Run controlled request volume below expected threshold:
```bash
for i in $(seq 1 20); do curl -k -s -o /dev/null -w "%{http_code}\n" https://alpha.sentinel.local/api/v1/events; done
```
Majority should be `200` (not persistent `429`).

## 6) Backend cannot reach internet (NAT routing broken)

### Detect
On backend:
```bash
curl -I https://aws.amazon.com
ping -c 2 8.8.8.8
ip route
```

On nat:
```bash
sudo sysctl net.ipv4.ip_forward
sudo iptables -t nat -S
```

### Most likely cause
- Private route table missing default route to NAT instance ENI
- NAT instance `source_dest_check` not disabled
- NAT iptables or forwarding not configured

### Fix
Re-apply Terraform:
```bash
cd infra
terraform apply
```

On nat instance, reapply forwarding rules if needed:
```bash
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -s 10.0.10.0/24 -o "$(ip route get 8.8.8.8 | awk '{print $5; exit}')" -j MASQUERADE
sudo netfilter-persistent save
```

### Verify
On backend:
```bash
curl -I https://aws.amazon.com
```
Must return HTTP headers successfully.

## 7) Tenant API key returning 401

### Detect
```bash
curl -i -H "X-Tenant-Key: <key>" https://alpha.sentinel.local/api/v1/events
```
Returns `401 Unauthorized`.

Check aggregator logs:
```bash
sudo journalctl -u aggregator -n 200 --no-pager
```

### Most likely cause
- Wrong API key value
- `tenants.yaml` missing/invalid `api_key`
- Aggregator loaded wrong tenant config path

### Fix
Inspect tenant config file and key values:
```bash
sudo cat /opt/sentinel/sentinel-network/watcher-service/config/tenants.yaml
```

Confirm env path used by aggregator (`TENANT_CONFIG`/`TENANT_CONFIG_PATH`) and restart:
```bash
sudo systemctl restart aggregator
```

### Verify
Re-test endpoint with known valid key:
```bash
curl -i -H "X-Tenant-Key: <valid-key>" https://alpha.sentinel.local/api/v1/events
```
Should return `200`.

## 8) New address added via API not being watched

### Detect
Add address call returns success but no related events appear:
```bash
curl -i -X POST \
  -H "Content-Type: application/json" \
  -H "X-Tenant-Key: <valid-key>" \
  -d '{"address":"0x..."}' \
  https://alpha.sentinel.local/api/v1/addresses
```

Then check watcher logs:
```bash
sudo journalctl -u watcher -n 200 --no-pager
```

### Most likely cause
- Address write did not persist to tenant config file
- Watcher reading different config path than aggregator writes
- Address invalid/non-checksummed formatting mismatch

### Fix
Confirm address exists in tenants file:
```bash
sudo grep -n "watch_addresses" -A20 /opt/sentinel/sentinel-network/watcher-service/config/tenants.yaml
```

Restart watcher to force immediate reload:
```bash
sudo systemctl restart watcher
```

Check watcher config/env alignment:
```bash
sudo systemctl show watcher | grep -E "Environment|ExecStart"
```

### Verify
- Watcher logs show monitoring activity including the new address context
- Tenant event endpoint starts returning transactions for that address:
```bash
curl -k -H "X-Tenant-Key: <valid-key>" "https://alpha.sentinel.local/api/v1/events/by-address/<address>"
```
