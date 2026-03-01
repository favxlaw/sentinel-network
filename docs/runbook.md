# Sentinel Network Runbook

## Service Status
On the backend instance:
```bash
sudo systemctl status blockchain-proxy.service
sudo systemctl status ipfs-node.service
sudo systemctl status sentinel-watcher.service
sudo systemctl status sentinel-aggregator.service
```

On the NGINX instance:
```bash
sudo systemctl status nginx
```

## Health Checks
Backend:
```bash
curl http://127.0.0.1:8545/health
curl http://127.0.0.1:9001/health
curl http://127.0.0.1:8000/health
```

NGINX (from your machine):
```bash
curl -k -H "Host: alpha.sentinel.local" https://<nginx_public_ip>/health
```

## Logs
Backend:
```bash
sudo journalctl -u blockchain-proxy.service -n 200 --no-pager
sudo journalctl -u sentinel-watcher.service -n 200 --no-pager
sudo journalctl -u sentinel-aggregator.service -n 200 --no-pager
sudo journalctl -u ipfs-node.service -n 200 --no-pager
```

NGINX:
```bash
sudo tail -n 200 /var/log/nginx/access.log
sudo tail -n 200 /var/log/nginx/error.log
```

## Common Failures
1. **Watcher not starting**
   - Check RPC keys in `/etc/sentinel/sentinel.env`.
   - Verify blockchain proxy health.
2. **Aggregator 401s**
   - Check tenant API keys in `/etc/sentinel/sentinel.env`.
   - Ensure `TENANT_CONFIG_PATH` resolves and values are interpolated.
3. **IPFS errors**
   - Verify `ipfs/docker-compose.yml` exists.
   - Ensure `swarm.key` is present at `/opt/sentinel/sentinel-network/ipfs/swarm.key`.
4. **NGINX 502**
   - Confirm backend private IP matches `nginx/nginx.conf`.
   - Ensure aggregator is listening on port `8000`.
