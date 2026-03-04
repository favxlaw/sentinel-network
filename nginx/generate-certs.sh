#!/bin/bash
set -euo pipefail

BASE_DOMAIN="${1:-}"
SSL_DIR="${2:-/etc/nginx/ssl}"

if [[ -z "${BASE_DOMAIN}" ]]; then
  echo "Usage: $0 <base_domain> [ssl_dir]"
  exit 1
fi

mkdir -p "${SSL_DIR}"

openssl req -x509 -nodes -newkey rsa:2048 -sha256 -days 365 \
  -keyout "${SSL_DIR}/wildcard.${BASE_DOMAIN}.key" \
  -out "${SSL_DIR}/wildcard.${BASE_DOMAIN}.crt" \
  -subj "/CN=*.${BASE_DOMAIN}" \
  -addext "subjectAltName=DNS:*.${BASE_DOMAIN},DNS:${BASE_DOMAIN}"
