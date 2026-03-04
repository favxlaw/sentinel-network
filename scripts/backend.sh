#!/bin/bash
set -euo pipefail

APP_DIR="/opt/sentinel/sentinel-network"
VENV="/opt/sentinel/venv"
SENTINEL_USER="sentinel"
ENV_DIR="/etc/sentinel"

# Create sentinel user if not exists
if ! id "$SENTINEL_USER" &>/dev/null; then
  useradd --system --no-create-home --shell /bin/false "$SENTINEL_USER"
fi

# Create env config directory
mkdir -p "$ENV_DIR"
chmod 750 "$ENV_DIR"
chown root:"$SENTINEL_USER" "$ENV_DIR"

# Create shared virtualenv
python3 -m venv "$VENV"
"$VENV/bin/pip" install --upgrade pip

# Install dependencies per service
"$VENV/bin/pip" install -r "$APP_DIR/blockchain-proxy/requirements.txt"
"$VENV/bin/pip" install -r "$APP_DIR/watcher-service/requirements.txt"

# Aggregator has no requirements.txt so install inferred deps
"$VENV/bin/pip" install fastapi uvicorn pydantic python-dotenv pyyaml requests

# Install IPFS (Kubo)
KUBO_VERSION="v0.24.0"
ARCH="linux-amd64"
curl -fsSL "https://dist.ipfs.tech/kubo/${KUBO_VERSION}/kubo_${KUBO_VERSION}_${ARCH}.tar.gz" \
  | tar -xz -C /tmp
mv /tmp/kubo/ipfs /usr/local/bin/ipfs
chmod +x /usr/local/bin/ipfs

# Initialize IPFS repo
mkdir -p /data/ipfs
chown -R "$SENTINEL_USER":"$SENTINEL_USER" /data/ipfs
sudo -u "$SENTINEL_USER" IPFS_PATH=/data/ipfs ipfs init

# Copy env files from repo examples if real ones don't exist
for svc in blockchain-proxy watcher aggregator; do
  if [ ! -f "$ENV_DIR/${svc}.env" ]; then
    if [ -f "$APP_DIR/${svc}/.env.example" ]; then
      cp "$APP_DIR/${svc}/.env.example" "$ENV_DIR/${svc}.env"
      chmod 640 "$ENV_DIR/${svc}.env"
      chown root:"$SENTINEL_USER" "$ENV_DIR/${svc}.env"
    fi
  fi
done

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

systemctl enable blockchain-proxy
systemctl start blockchain-proxy

systemctl enable aggregator
systemctl start aggregator

systemctl enable watcher
systemctl start watcher

echo "All Sentinel services installed and started"

