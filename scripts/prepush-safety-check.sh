#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

echo "[pre-push] running safety checks..."

# 1) Block common sensitive files from being tracked
blocked_paths='(^|/)\.env$|\.pem$|\.key$|(^|/)terraform\.tfstate(\.backup)?$|(^|/).+\.tfvars$|(^|/)ipfs/data/'
if git ls-files | rg -n "$blocked_paths" >/tmp/sentinel_blocked_paths.txt; then
  echo "[pre-push] blocked tracked files found:"
  cat /tmp/sentinel_blocked_paths.txt
  echo "[pre-push] remove from index before push (files stay local):"
  echo "  git rm -r --cached ipfs/data"
  echo "  git rm --cached <file>"
  exit 1
fi

# 2) Quick staged-content secret pattern scan
staged_content="$(git diff --cached -- . ':(exclude).env.example' ':(exclude)**/.env.example' || true)"
if printf "%s" "$staged_content" | rg -n -i \
  'aws_secret_access_key|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY|x-tenant-key:\s*[a-z0-9_\-]{12,}|alchemy_api_key:\s*[^\s$]|infura_api_key:\s*[^\s$]|token\s*=\s*[^"'"'"'[:space:]]{12,}|password\s*=\s*[^"'"'"'[:space:]]{8,}' \
  >/tmp/sentinel_staged_secrets.txt; then
  echo "[pre-push] possible secret-like values detected in staged changes:"
  cat /tmp/sentinel_staged_secrets.txt
  echo "[pre-push] review and remove secrets before push."
  exit 1
fi

echo "[pre-push] checks passed."
