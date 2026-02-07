#!/bin/bash
set -e

# Bastion Host Setup Script
# This script configures the bastion host for SSH access to private resources

echo "=== Starting Bastion Host Setup ===" | logger -t sentinel

# Update system
yum update -y
yum install -y aws-cli aws-ec2-instance-connect

# Configure CloudWatch Logs
yum install -y awslogs
systemctl start awslogsd
systemctl enable awslogsd

# Disable root login and password authentication
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl reload sshd

# Create security audit logs directory
mkdir -p /var/log/bastion
chmod 700 /var/log/bastion

# Add security audit logging to sshd
cat >> /etc/ssh/sshd_config <<'EOF'

# Session recording
ForceCommand /usr/local/bin/audit-wrapper
EOF

# Create audit wrapper script
cat > /usr/local/bin/audit-wrapper <<'EOF'
#!/bin/bash
echo "[$(date '+%Y-%m-%d %H:%M:%S')] User: ${SSH_ORIGINAL_COMMAND}" >> /var/log/bastion/session.log
echo "[$(date '+%Y-%m-%d %H:%M:%S')] From: ${SSH_CLIENT%% *}" >> /var/log/bastion/session.log
exec $SSH_ORIGINAL_COMMAND
EOF

chmod +x /usr/local/bin/audit-wrapper

# Install CloudWatch monitoring tools
yum install -y amazon-cloudwatch-agent

# Create monitoring configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'EOF'
{
  "metrics": {
    "namespace": "Sentinel/Bastion",
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
      "disk": {
        "measurement": [
          {
            "name": "used_percent",
            "rename": "DISK_USED",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "/"
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
            "file_path": "/var/log/bastion/session.log",
            "log_group_name": "/sentinel/bastion/sessions",
            "log_stream_name": "{instance_id}"
          },
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
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

echo "=== Bastion Host Setup Complete ===" | logger -t sentinel
