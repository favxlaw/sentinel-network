# Tenant Onboarding

## Add a New Tenant
1. Edit `config/tenants.yaml` and add a new tenant entry.
2. Create a strong API key and store it in `/etc/sentinel/sentinel.env` on the backend instance.
3. Add watch addresses and alert threshold.
4. Restart the aggregator and watcher services.

Example:
```yaml
tenants:
  dao-delta:
    id: dao-delta
    api_key: ${DAO_DELTA_API_KEY}
    watch_addresses:
      - "0xabc..."
    alert_threshold_eth: 12.5
    rate_limit_per_min: 120
```

Backend env file:
```bash
DAO_DELTA_API_KEY="replace-with-strong-key"
```

Restart services:
```bash
sudo systemctl restart sentinel-watcher.service
sudo systemctl restart sentinel-aggregator.service
```

## Update NGINX
1. Add a new server block for `delta.sentinel.local`.
2. Add a new rate limit zone if needed.
3. Reload NGINX:
```bash
sudo nginx -t && sudo systemctl reload nginx
```
