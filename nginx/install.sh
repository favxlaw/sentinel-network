#!/bin/bash
set -euo pipefail

BACKEND_IP="${1:-${BACKEND_IP:-}}"
BACKEND_PORT="${2:-${BACKEND_PORT:-}}"
TENANT_IDS_JSON="${3:-${TENANT_IDS_JSON:-}}"
TENANT_RATE_LIMITS_JSON="${4:-${TENANT_RATE_LIMITS_JSON:-}}"
BASE_DOMAIN="${5:-${BASE_DOMAIN:-sentinel.local}}"

if [[ -z "${BACKEND_IP}" || -z "${BACKEND_PORT}" || -z "${TENANT_IDS_JSON}" || -z "${TENANT_RATE_LIMITS_JSON}" ]]; then
  echo "Usage: $0 <backend_ip> <backend_port> <tenant_ids_json> <tenant_rate_limits_json> [base_domain]"
  echo "Or provide BACKEND_IP, BACKEND_PORT, TENANT_IDS_JSON, TENANT_RATE_LIMITS_JSON, BASE_DOMAIN via environment."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSL_DIR="/etc/nginx/ssl"
TENANT_CONF_DIR="/etc/nginx/tenant-configs"
TENANT_GEN_DIR="${TENANT_CONF_DIR}/generated"
ERROR_DIR="/var/www/sentinel/errors"

apt-get update -y
apt-get install -y nginx openssl jq

mkdir -p "${SSL_DIR}" "${TENANT_CONF_DIR}" "${TENANT_GEN_DIR}" "${ERROR_DIR}"
rm -f "${TENANT_CONF_DIR}"/*.conf "${TENANT_GEN_DIR}"/*.conf "${ERROR_DIR}"/*.html

bash "${SCRIPT_DIR}/generate-certs.sh" "${BASE_DOMAIN}" "${SSL_DIR}"

cp "${SCRIPT_DIR}/nginx.conf" /etc/nginx/nginx.conf

RATE_LIMIT_FILE="${TENANT_GEN_DIR}/rate-limit-zones.conf"
: > "${RATE_LIMIT_FILE}"

for tenant_id in $(echo "${TENANT_IDS_JSON}" | jq -r '.[]'); do
  rate_limit="$(echo "${TENANT_RATE_LIMITS_JSON}" | jq -r --arg tenant "${tenant_id}" '.[$tenant] // empty')"
  if [[ -z "${rate_limit}" ]]; then
    echo "Missing rate limit for tenant: ${tenant_id}"
    exit 1
  fi

  zone_name="$(echo "${tenant_id}" | tr '-' '_')_zone"
  printf 'limit_req_zone $binary_remote_addr zone=%s:10m rate=%sr/m;\n' "${zone_name}" "${rate_limit}" >> "${RATE_LIMIT_FILE}"
done

for tenant_id in $(echo "${TENANT_IDS_JSON}" | jq -r '.[]'); do
  rate_limit="$(echo "${TENANT_RATE_LIMITS_JSON}" | jq -r --arg tenant "${tenant_id}" '.[$tenant]')"
  subdomain_prefix="${tenant_id##*-}"
  fqdn="${subdomain_prefix}.${BASE_DOMAIN}"
  zone_name="$(echo "${tenant_id}" | tr '-' '_')_zone"
  tenant_conf_path="${TENANT_CONF_DIR}/${tenant_id}.conf"
  tenant_error_page="${tenant_id}-429.html"

  cat > "${ERROR_DIR}/${tenant_error_page}" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Too Many Requests</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body { font-family: sans-serif; margin: 2rem; max-width: 40rem; }
  </style>
</head>
<body>
  <h1>Rate limit reached</h1>
  <p>Tenant: ${tenant_id}</p>
  <p>Allowed rate: ${rate_limit} requests/minute.</p>
  <p>Please retry later.</p>
</body>
</html>
EOF

  cat > "${tenant_conf_path}" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${fqdn};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${fqdn};

    ssl_certificate ${SSL_DIR}/wildcard.${BASE_DOMAIN}.crt;
    ssl_certificate_key ${SSL_DIR}/wildcard.${BASE_DOMAIN}.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_prefer_server_ciphers off;

    error_page 429 /errors/${tenant_error_page};

    location = /errors/${tenant_error_page} {
        root /var/www/sentinel;
        internal;
    }

    location / {
        limit_req zone=${zone_name} burst=20 nodelay;

        proxy_pass http://${BACKEND_IP}:${BACKEND_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Tenant-ID "${tenant_id}";
        proxy_connect_timeout 5s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF
done

nginx -t
systemctl enable nginx
systemctl restart nginx
