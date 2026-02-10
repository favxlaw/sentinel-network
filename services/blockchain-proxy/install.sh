#!/bin/bash
set -euo pipefail

SERVICE_NAME="blockchain-proxy.service"
APP_DIR="/opt/sentinel/sentinel-network/blockchain-proxy"
VENV_DIR="${APP_DIR}/venv"
SERVICE_SRC="/opt/sentinel/sentinel-network/services/blockchain-proxy/${SERVICE_NAME}"
SERVICE_DST="/etc/systemd/system/${SERVICE_NAME}"

if [ ! -d "${APP_DIR}" ]; then
  echo "ERROR: ${APP_DIR} not found. Repo must be cloned to /opt/sentinel/sentinel-network." >&2
  exit 1
fi

# Create venv and install deps
if [ ! -d "${VENV_DIR}" ]; then
  python3 -m venv "${VENV_DIR}"
fi
"${VENV_DIR}/bin/pip" install --upgrade pip
"${VENV_DIR}/bin/pip" install -r "${APP_DIR}/requirements.txt"

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
