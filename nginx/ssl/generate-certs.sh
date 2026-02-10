#!/bin/bash
set -euo pipefail

SSL_DIR="/etc/nginx/ssl"
DOMAIN="*.sentinel.local"

sudo mkdir -p "${SSL_DIR}"

sudo openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout "${SSL_DIR}/sentinel.key" \
  -out "${SSL_DIR}/sentinel.crt" \
  -subj "/CN=${DOMAIN}"

echo "Generated self-signed cert for ${DOMAIN} in ${SSL_DIR}"
