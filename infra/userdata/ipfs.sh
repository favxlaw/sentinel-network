#!/bin/bash
set -e

# IPFS Node Installation and Configuration Script
# Variables will be substituted by Terraform

IPFS_VERSION="${ipfs_version}"
IPFS_PATH="${ipfs_path}"
IPFS_API_PORT="${ipfs_api_port}"
IPFS_USER="ubuntu"

echo "=== Starting IPFS Installation ===" | logger -t sentinel
echo "IPFS Version: $IPFS_VERSION" | logger -t sentinel
echo "IPFS Path: $IPFS_PATH" | logger -t sentinel

# Update system
yum update -y
yum install -y aws-cli git wget curl jq

# Install CloudWatch agent
yum install -y amazon-cloudwatch-agent

# Create application user if needed
if ! id -u "$IPFS_USER" &>/dev/null; then
  useradd -m -s /bin/bash "$IPFS_USER"
fi

# Create IPFS directories
mkdir -p "$IPFS_PATH"
chown -R "$IPFS_USER:$IPFS_USER" "$IPFS_PATH"

# Format and mount data volume if available
if [ -b /dev/nvme1n1 ]; then
  echo "Formatting data volume..." | logger -t sentinel
  mkfs.ext4 -F /dev/nvme1n1
  mkdir -p /var/lib/ipfs-data
  mount /dev/nvme1n1 /var/lib/ipfs-data
  chown -R "$IPFS_USER:$IPFS_USER" /var/lib/ipfs-data
  
  # Add to fstab for persistence
  echo "/dev/nvme1n1 /var/lib/ipfs-data ext4 defaults,nofail 0 2" >> /etc/fstab
fi

# Download and install IPFS Kubo
cd /tmp
echo "Downloading IPFS Kubo $IPFS_VERSION..." | logger -t sentinel
wget "https://dist.ipfs.tech/kubo/${IPFS_VERSION}/kubo_${IPFS_VERSION}_linux-amd64.tar.gz"
tar -xvzf "kubo_${IPFS_VERSION}_linux-amd64.tar.gz"
cd kubo
bash install.sh

# Initialize IPFS repository
export IPFS_PATH="$IPFS_PATH"
export HOME="/home/$IPFS_USER"

echo "Initializing IPFS repository..." | logger -t sentinel
sudo -u "$IPFS_USER" -E bash -c "ipfs init --profile=server"

# Configure IPFS for private network
echo "Configuring IPFS..." | logger -t sentinel
sudo -u "$IPFS_USER" -E bash -c "ipfs config --json AutoConf.Enabled false"
sudo -u "$IPFS_USER" -E bash -c "ipfs bootstrap rm --all"

# Configure API and Gateway addresses
sudo -u "$IPFS_USER" -E bash -c "ipfs config Addresses.API /ip4/0.0.0.0/tcp/$IPFS_API_PORT"
sudo -u "$IPFS_USER" -E bash -c "ipfs config Addresses.Gateway /ip4/0.0.0.0/tcp/8080"

# Increase file descriptor limits
cat > /etc/security/limits.d/ipfs.conf <<'EOF'
# IPFS file descriptor limits
ubuntu soft nofile 1000000
ubuntu hard nofile 1000000
ubuntu soft nproc 512
ubuntu hard nproc 512
EOF

# Create systemd service for IPFS
cat > /etc/systemd/system/ipfs.service <<'EOFSERVICE'
[Unit]
Description=IPFS Daemon
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=$IPFS_USER
Environment="IPFS_PATH=$IPFS_PATH"
Environment="LIBP2P_FORCE_PNET=1"
ExecStart=/usr/local/bin/ipfs daemon --enable-gc
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ipfs

# Resource limits
LimitNOFILE=1000000
LimitNPROC=512

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$IPFS_PATH

[Install]
WantedBy=multi-user.target
EOFSERVICE

# Create CloudWatch monitoring configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'EOFCW'
{
  "metrics": {
    "namespace": "Sentinel/IPFS",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          {
            "name": "cpu_usage_idle",
            "rename": "CPU_IDLE",
            "unit": "Percent"
          },
          {
            "name": "cpu_usage_system",
            "rename": "CPU_SYSTEM",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": [
          {
            "name": "used_percent",
            "rename": "DISK_USED",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 300,
        "resources": [
          "/",
          "/var/lib/ipfs-data"
        ]
      },
      "mem": {
        "measurement": [
          {
            "name": "mem_used_percent",
            "rename": "MEM_USED",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 60
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/sentinel/ipfs/system",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
EOFCW

# Start IPFS service
systemctl daemon-reload
systemctl enable ipfs
systemctl start ipfs

# Wait for IPFS to initialize
sleep 10

# Verify IPFS is running
if pgrep -u "$IPFS_USER" ipfs > /dev/null; then
  echo "IPFS daemon running successfully" | logger -t sentinel
else
  echo "ERROR: IPFS daemon failed to start" | logger -t sentinel
  exit 1
fi

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

echo "=== IPFS Installation Complete ===" | logger -t sentinel