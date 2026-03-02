#!/bin/bash
set -euo pipefail

# NGINX gateway setup (Ubuntu 22.04)
apt-get update -y
apt-get install -y git

REPO_URL="https://github.com/your-org/sentinel-network.git"
APP_ROOT="/opt/sentinel"
APP_DIR="${APP_ROOT}/sentinel-network"

mkdir -p "${APP_ROOT}"
if [ ! -d "${APP_DIR}" ]; then
  git clone "${REPO_URL}" "${APP_DIR}"
fi

# Run nginx installer from repo
if [ -f "${APP_DIR}/nginx/install.sh" ]; then
  bash "${APP_DIR}/nginx/install.sh"
fi
