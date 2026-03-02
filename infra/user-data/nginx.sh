#!/bin/bash
set -euo pipefail

apt-get update -y
apt-get install -y git

# SSM agent is pre-installed via snap on Ubuntu 22.04 AWS AMI
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent
systemctl start snap.amazon-ssm-agent.amazon-ssm-agent

REPO_URL="https://github.com/favxlaw/sentinel-network.git"
APP_ROOT="/opt/sentinel"
APP_DIR="${APP_ROOT}/sentinel-network"

mkdir -p "${APP_ROOT}"
if [ ! -d "${APP_DIR}" ]; then
  git clone "${REPO_URL}" "${APP_DIR}"
fi

if [ -f "${APP_DIR}/nginx/install.sh" ]; then
  bash "${APP_DIR}/nginx/install.sh"
fi