#!/bin/bash
set -euo pipefail

APP_DIR="/opt/sentinel/sentinel-network"
VENV="/opt/sentinel/venv"
SENTINEL_USER="sentinel"
ENV_DIR="/etc/sentinel"
LOG_DIR="/var/log/sentinel"
DATA_DIR="/data"

# Create sentinel user if not exists
if ! id "$SENTINEL_USER" &>/dev/null; then
  useradd --system --no-create-home --shell /bin/false "$SENTINEL_USER"
fi

# Create required directories
mkdir -p "$ENV_DIR"
chmod 755 "$ENV_DIR"
chown root:"$SENTINEL_USER" "$ENV_DIR"

mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"
chown "$SENTINEL_USER":"$SENTINEL_USER" "$LOG_DIR"

mkdir -p "$DATA_DIR/ipfs"
chown -R "$SENTINEL_USER":"$SENTINEL_USER" "$DATA_DIR"

# Create shared virtualenv
python3 -m venv "$VENV"
"$VENV/bin/pip" install --upgrade pip

# Install dependencies per service
"$VENV/bin/pip" install -r "$APP_DIR/blockchain-proxy/requirements.txt"
"$VENV/bin/pip" install -r "$APP_DIR/watcher-service/requirements.txt"
"$VENV/bin/pip" install fastapi uvicorn pydantic python-dotenv pyyaml requests

# Install IPFS (Kubo)
KUBO_VERSION="v0.24.0"
ARCH="linux-amd64"
curl -fsSL "https://dist.ipfs.tech/kubo/${KUBO_VERSION}/kubo_${KUBO_VERSION}_${ARCH}.tar.gz" \
  | tar -xz -C /tmp
mv /tmp/kubo/ipfs /usr/local/bin/ipfs
chmod +x /usr/local/bin/ipfs

# Initialize IPFS repo
sudo -u "$SENTINEL_USER" IPFS_PATH=/data/ipfs ipfs init

# Configure IPFS private network mode
sudo -u "$SENTINEL_USER" IPFS_PATH=/data/ipfs ipfs bootstrap rm --all
sudo -u "$SENTINEL_USER" IPFS_PATH=/data/ipfs ipfs config Addresses.API /ip4/127.0.0.1/tcp/5001
sudo -u "$SENTINEL_USER" IPFS_PATH=/data/ipfs ipfs config Addresses.Gateway /ip4/127.0.0.1/tcp/8080

# Generate swarm key for private network
python3 -c "
import secrets
print('/key/swarm/psk/1.0.0/')
print('/base16/')
print(secrets.token_hex(32))
" > /data/ipfs/swarm.key
chmod 600 /data/ipfs/swarm.key
chown "$SENTINEL_USER":"$SENTINEL_USER" /data/ipfs/swarm.key

# Create tenants.yaml if it doesn't exist
TENANT_CONFIG="$APP_DIR/watcher-service/config/tenants.yaml"
mkdir -p "$(dirname $TENANT_CONFIG)"
if [ ! -f "$TENANT_CONFIG" ]; then
  cat > "$TENANT_CONFIG" << 'EOF'
tenants:
  - id: "dao-alpha"
    api_key: "CHANGE_ME_ALPHA"
    watch_addresses: []
    alert_threshold_eth: 10

  - id: "dao-beta"
    api_key: "CHANGE_ME_BETA"
    watch_addresses: []
    alert_threshold_eth: 10

  - id: "dao-gamma"
    api_key: "CHANGE_ME_GAMMA"
    watch_addresses: []
    alert_threshold_eth: 10
EOF
fi
chown "$SENTINEL_USER":"$SENTINEL_USER" "$TENANT_CONFIG"
chmod 664 "$TENANT_CONFIG"

# Create env files if they don't exist
# Blockchain proxy env
if [ ! -f "$ENV_DIR/blockchain-proxy.env" ]; then
  cat > "$ENV_DIR/blockchain-proxy.env" << EOF
ALCHEMY_API_KEY=CHANGE_ME
RPC_URL=https://eth-sepolia.g.alchemy.com/v2/
RPC_PROVIDER=alchemy
CACHE_BACKEND=memory
CACHE_TTL_SECONDS=300
REQUEST_TIMEOUT=10
MAX_RETRIES=3
PORT=8545
LOG_LEVEL=INFO
LOG_DIR=${LOG_DIR}
EOF
  chmod 640 "$ENV_DIR/blockchain-proxy.env"
  chown root:"$SENTINEL_USER" "$ENV_DIR/blockchain-proxy.env"
fi

# Watcher env
if [ ! -f "$ENV_DIR/watcher.env" ]; then
  cat > "$ENV_DIR/watcher.env" << EOF
ALCHEMY_API_KEY=CHANGE_ME
RPC_URL=https://eth-sepolia.g.alchemy.com/v2/
POLL_INTERVAL=12
IPFS_API_URL=http://127.0.0.1:5001
LOG_LEVEL=INFO
TENANT_CONFIG=${TENANT_CONFIG}
DB_PATH=${DATA_DIR}/sentinel.db
LOG_DIR=${LOG_DIR}
EOF
  chmod 640 "$ENV_DIR/watcher.env"
  chown root:"$SENTINEL_USER" "$ENV_DIR/watcher.env"
fi

# Aggregator env
if [ ! -f "$ENV_DIR/aggregator.env" ]; then
  cat > "$ENV_DIR/aggregator.env" << EOF
TENANT_CONFIG_PATH=${TENANT_CONFIG}
SENTINEL_DB_PATH=${APP_DIR}/watcher-service/watcher.db
API_HOST=0.0.0.0
API_PORT=8006
IPFS_HOST=127.0.0.1
IPFS_PORT=5001
LOG_LEVEL=INFO
ENVIRONMENT=production
EOF
  chmod 640 "$ENV_DIR/aggregator.env"
  chown root:"$SENTINEL_USER" "$ENV_DIR/aggregator.env"
fi

# Install systemd units
cp "$APP_DIR/services/blockchain-proxy/blockchain-proxy.service" /etc/systemd/system/
cp "$APP_DIR/services/watcher/watcher.service" /etc/systemd/system/
cp "$APP_DIR/services/aggregator/aggregator.service" /etc/systemd/system/
cp "$APP_DIR/services/ipfs/ipfs-node.service" /etc/systemd/system/

# Set correct ownership on app dir
chown -R "$SENTINEL_USER":"$SENTINEL_USER" "$APP_DIR"
chown -R "$SENTINEL_USER":"$SENTINEL_USER" "$VENV"

# Enable and start services in dependency order
systemctl daemon-reload

systemctl enable ipfs-node
systemctl start ipfs-node
sleep 5

systemctl enable blockchain-proxy
systemctl start blockchain-proxy
sleep 5

systemctl enable aggregator
systemctl start aggregator
sleep 3

systemctl enable watcher
systemctl start watcher
sleep 15

# Skip watcher backlog - set to current block
echo "Setting watcher to current block to skip backlog..."
LATEST_HEX=$(curl -sS -X POST http://localhost:8545/rpc \
  -H "Content-Type: application/json" \
  -H "X-Tenant-ID: dao-alpha" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | \
  python3 -c "import sys,json; h=json.load(sys.stdin)['result']; print(int(h,16))" 2>/dev/null || echo "0")

if [ "$LATEST_HEX" != "0" ]; then
  systemctl stop watcher
  sleep 2
  sudo -u "$SENTINEL_USER" sqlite3 "$APP_DIR/watcher-service/watcher.db" \
    "INSERT OR REPLACE INTO watcher_state (key,value) VALUES ('last_processed_block','$LATEST_HEX');" || true
  systemctl start watcher
  echo "Watcher set to block $LATEST_HEX"
else
  echo "Warning: Could not get latest block - watcher will start from beginning"
fi

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF_CW'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "namespace": "Sentinel/Backend",
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_idle"],
        "metrics_collection_interval": 60
      },
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["disk_used_percent"],
        "resources": ["/", "/data"],
        "metrics_collection_interval": 60
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/sentinel/*.log",
            "log_group_name": "/sentinel/backend",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
EOF_CW

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

echo "============================================"
echo "All Sentinel services installed and started"
echo "============================================"
echo ""
echo "IMPORTANT - Manual steps required:"
echo "1. Update Alchemy API key:"
echo "   sudo nano /etc/sentinel/blockchain-proxy.env"
echo "   sudo nano /etc/sentinel/watcher.env"
echo ""
echo "2. Update tenant API keys:"
echo "   sudo nano $TENANT_CONFIG"
echo "   Generate keys with: python3 -c \"import secrets; print(secrets.token_hex(32))\""
echo ""
echo "3. Restart services after updating keys:"
echo "   sudo systemctl restart blockchain-proxy aggregator watcher"
echo "============================================"

