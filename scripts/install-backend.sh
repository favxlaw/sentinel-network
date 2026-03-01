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
