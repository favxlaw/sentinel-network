#!/bin/bash
set -euo pipefail

REPO_ROOT="/opt/sentinel/sentinel-network"
NGINX_DIR="${REPO_ROOT}/nginx"

if [ ! -d "${NGINX_DIR}" ]; then
  echo "ERROR: ${NGINX_DIR} not found. Repo must be cloned to /opt/sentinel/sentinel-network." >&2
  exit 1
fi

sudo apt-get update -y
sudo apt-get install -y nginx openssl

# Copy configuration and assets
sudo cp "${NGINX_DIR}/nginx.conf" /etc/nginx/nginx.conf
sudo mkdir -p /etc/nginx/errors
sudo cp "${NGINX_DIR}/errors/429-dao-alpha.html" /etc/nginx/errors/429-dao-alpha.html
sudo cp "${NGINX_DIR}/errors/429-dao-beta.html" /etc/nginx/errors/429-dao-beta.html
sudo cp "${NGINX_DIR}/errors/429-dao-gamma.html" /etc/nginx/errors/429-dao-gamma.html

# Generate certs
bash "${NGINX_DIR}/ssl/generate-certs.sh"

sudo systemctl enable nginx
sudo systemctl restart nginx

if ! sudo systemctl is-active --quiet nginx; then
  echo "ERROR: nginx failed to start" >&2
  sudo systemctl status nginx --no-pager
  exit 1
fi

echo "OK: nginx is running"
