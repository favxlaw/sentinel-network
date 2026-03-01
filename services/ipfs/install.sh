#!/bin/bash
set -euo pipefail

SERVICE_NAME="ipfs-node.service"
APP_DIR="/opt/sentinel/sentinel-network/ipfs"
SERVICE_SRC="/opt/sentinel/sentinel-network/services/ipfs/${SERVICE_NAME}"
SERVICE_DST="/etc/systemd/system/${SERVICE_NAME}"

if [ ! -d "${APP_DIR}" ]; then
  echo "ERROR: ${APP_DIR} not found. Repo must be cloned to /opt/sentinel/sentinel-network." >&2
  exit 1
fi

# Install Docker (if not present)
if ! command -v docker >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y docker.io
  sudo systemctl enable docker
  sudo systemctl start docker
fi

# Ensure Docker Compose v2 is available
if ! docker compose version >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y docker-compose-plugin
fi

# Create IPFS data directory
sudo mkdir -p /data/ipfs
sudo chown -R ubuntu:ubuntu /data/ipfs

# Install systemd unit
if [ ! -f "${SERVICE_SRC}" ]; then
  echo "ERROR: ${SERVICE_SRC} not found." >&2
  exit 1
fi
sudo cp "${SERVICE_SRC}" "${SERVICE_DST}"

sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}"
sudo systemctl restart "${SERVICE_NAME}"

# Verify service
if ! sudo systemctl is-active --quiet "${SERVICE_NAME}"; then
  echo "ERROR: ${SERVICE_NAME} failed to start" >&2
  sudo systemctl status "${SERVICE_NAME}" --no-pager
  exit 1
fi

echo "OK: ${SERVICE_NAME} is running"
