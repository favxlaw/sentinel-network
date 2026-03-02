#!/bin/bash
set -e

# Backend setup: Docker, Python, Git, then install backend
apt-get update -y
apt-get install -y docker.io docker-compose python3 python3-pip python3-venv git amazon-cloudwatch-agent amazon-ssm-agent
systemctl enable docker
systemctl start docker
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Create /data directory for SQLite and IPFS
mkdir -p /data

# Mount data volume at /data if present
DATA_DEVICE=""
for dev in /dev/nvme1n1 /dev/xvdf /dev/sdf; do
  if [ -b "$dev" ]; then
    DATA_DEVICE="$dev"
    break
  fi
done

if [ -n "$DATA_DEVICE" ]; then
  mkfs.ext4 -F "$DATA_DEVICE"
  mount "$DATA_DEVICE" /data
  echo "$DATA_DEVICE /data ext4 defaults,nofail 0 2" >> /etc/fstab
fi

REPO_URL="https://github.com/your-org/sentinel-network.git"
APP_ROOT="/opt/sentinel"
APP_DIR="${APP_ROOT}/sentinel-network"

mkdir -p "$APP_ROOT"
if [ ! -d "$APP_DIR" ]; then
  git clone "$REPO_URL" "$APP_DIR"
fi

if [ -f "$APP_DIR/scripts/install-backend.sh" ]; then
  bash "$APP_DIR/scripts/install-backend.sh"
fi
