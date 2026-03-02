#!/bin/bash
set -e

# NAT Instance Setup Script
# This script configures the NAT instance for private subnet internet access

echo "=== Starting NAT Instance Setup ===" | logger -t sentinel

# Update system
yum update -y
yum install -y aws-cli

# Enable IP forwarding
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

# Install and configure iptables
yum install -y iptables-services
systemctl enable iptables
systemctl start iptables

# Set up NAT rules
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i eth0 -o eth0 -j ACCEPT

# Allow DNS passthrough
iptables -A FORWARD -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -p tcp --dport 53 -j ACCEPT

# Save iptables rules
service iptables save

# Configure CloudWatch monitoring
yum install -y amazon-cloudwatch-agent

# Create monitoring configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'EOF'
{
  "metrics": {
    "namespace": "Sentinel/NAT",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          {
            "name": "cpu_usage_idle",
            "rename": "CPU_IDLE",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 60
      },
      "netstat": {
        "measurement": [
          {
            "name": "tcp_established",
            "rename": "TCP_ESTABLISHED",
            "unit": "Count"
          },
          {
            "name": "tcp_time_wait",
            "rename": "TCP_TIME_WAIT",
            "unit": "Count"
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
            "log_group_name": "/sentinel/nat/system",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Configure log rotation for NAT monitoring
cat > /etc/logrotate.d/nat-monitoring <<'EOF'
/var/log/nat-* {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
}
EOF

echo "=== NAT Instance Setup Complete ===" | logger -t sentinel
