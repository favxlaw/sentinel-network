#!/bin/bash
set -euo pipefail

echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4

# Wait for internet connectivity via NAT
echo "Waiting for internet connectivity..."
for i in $(seq 1 30); do
  if curl -fsS --max-time 5 http://checkip.amazonaws.com > /dev/null 2>&1; then
    echo "Internet reachable on attempt $i"
    break
  fi
  echo "Not reachable yet, waiting 10s... ($i/30)"
  sleep 10
  if [ "$i" -eq 30 ]; then
    echo "ERROR: Internet never became reachable, aborting"
    exit 1
  fi
done

# Now safe to apt
apt-get update -y
apt-get install -y python3 python3-pip python3-venv git curl ca-certificates gnupg lsb-release
apt-get install -y sqlite3

# Install Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable docker
systemctl start docker

# Install CloudWatch agent
curl -sO https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb
rm amazon-cloudwatch-agent.deb
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# SSM agent — snap is pre-installed on this AMI
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent
systemctl start snap.amazon-ssm-agent.amazon-ssm-agent

sleep 30
if ! systemctl is-active --quiet snap.amazon-ssm-agent.amazon-ssm-agent; then
  echo "WARNING: SSM agent failed to start, attempting restart..."
  systemctl restart snap.amazon-ssm-agent.amazon-ssm-agent
fi

# Mount data volume
mkdir -p /data
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

# Clone and install app
REPO_URL="https://github.com/favxlaw/sentinel-network.git"
APP_ROOT="/opt/sentinel"
APP_DIR="${APP_ROOT}/sentinel-network"

mkdir -p "$APP_ROOT"
if [ ! -d "$APP_DIR" ]; then
  git clone "$REPO_URL" "$APP_DIR"
fi

if [ -f "$APP_DIR/scripts/install-backend.sh" ]; then
  bash "$APP_DIR/scripts/install-backend.sh"
fi

