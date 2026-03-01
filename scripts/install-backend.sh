#!/bin/bash
set -euo pipefail

REPO_ROOT="/opt/sentinel/sentinel-network"

if [ ! -d "${REPO_ROOT}" ]; then
  echo "ERROR: ${REPO_ROOT} not found. Repo must be cloned first." >&2
  exit 1
fi

# Update packages and install global deps
sudo apt-get update -y
sudo apt-get install -y python3 python3-venv python3-pip git curl

# Ensure /data directory structure exists
sudo mkdir -p /data/sentinel
sudo chown -R ubuntu:ubuntu /data

# Ensure sentinel env file exists (do not overwrite if present)
sudo mkdir -p /etc/sentinel
if [ ! -f /etc/sentinel/sentinel.env ]; then
  cat <<'EOF_ENV' | sudo tee /etc/sentinel/sentinel.env >/dev/null
# Sentinel environment variables
# RPC provider
# RPC_URL="https://sepolia.infura.io/v3/your_key"
# ALCHEMY_API_KEY="your_alchemy_key"
# INFURA_API_KEY="your_infura_key"
#
# Tenant API keys
# DAO_ALPHA_API_KEY="replace-with-strong-key"
# DAO_BETA_API_KEY="replace-with-strong-key"
# DAO_GAMMA_API_KEY="replace-with-strong-key"
EOF_ENV
  sudo chmod 600 /etc/sentinel/sentinel.env
  sudo chown root:root /etc/sentinel/sentinel.env
fi

# Install services in order
bash "${REPO_ROOT}/services/blockchain-proxy/install.sh"
bash "${REPO_ROOT}/services/ipfs/install.sh"
bash "${REPO_ROOT}/services/watcher/install.sh"
bash "${REPO_ROOT}/services/aggregator/install.sh"

# Verify all services
for svc in blockchain-proxy.service ipfs-node.service sentinel-watcher.service sentinel-aggregator.service; do
  if ! sudo systemctl is-active --quiet "${svc}"; then
    echo "ERROR: ${svc} is not running" >&2
    sudo systemctl status "${svc}" --no-pager
    exit 1
  fi
  echo "OK: ${svc} is running"
done

echo "All backend services installed and running"
