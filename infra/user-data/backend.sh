#!/bin/bash
set -euo pipefail

# Force IPv4 for apt to avoid IPv6 connectivity issues
echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4

# Wait for NAT routing to be available before proceeding
for i in $(seq 1 10); do
  apt-get update -y && break
  echo "Network not ready, waiting 15s... (attempt $i/10)"
  sleep 15
done

# Install base packages
apt-get install -y python3 python3-pip python3-venv git curl ca-certificates gnupg lsb-release

# Install Docker via official Docker repo
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable docker
systemctl start docker

# Install CloudWatch agent from AWS
curl -sO https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb
rm amazon-cloudwatch-agent.deb
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# SSM agent is pre-installed via snap on Ubuntu 22.04 AWS AMI
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent
systemctl start snap.amazon-ssm-agent.amazon-ssm-agent

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

# Configure CloudWatch agent (if config is present in repo)
if [ -f "$APP_DIR/config/cloudwatch-agent.json" ]; then
  cp "$APP_DIR/config/cloudwatch-agent.json" /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
  /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
fi
