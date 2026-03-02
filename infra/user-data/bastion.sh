#!/bin/bash
set -euo pipefail

# Bastion + NAT setup (Ubuntu 22.04)
# - SSH hardening
# - NAT iptables for private subnet egress
# - CloudWatch agent

ADMIN_USER="ubuntu"
PRIVATE_CIDR="10.0.10.0/24"

apt-get update -y
apt-get install -y amazon-cloudwatch-agent iptables-persistent

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi

# NAT configuration
iptables -t nat -A POSTROUTING -s "${PRIVATE_CIDR}" -o eth0 -j MASQUERADE
iptables -A FORWARD -s "${PRIVATE_CIDR}" -o eth0 -j ACCEPT
iptables -A FORWARD -d "${PRIVATE_CIDR}" -m state --state ESTABLISHED,RELATED -i eth0 -j ACCEPT

netfilter-persistent save

# SSH hardening
sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl reload sshd

# CloudWatch agent minimal config
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'EOF_CW'
{
  "metrics": {
    "namespace": "Sentinel/Bastion",
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_idle"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/"],
        "metrics_collection_interval": 60
      },
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/auth.log",
            "log_group_name": "/sentinel/bastion/auth",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
EOF_CW

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
