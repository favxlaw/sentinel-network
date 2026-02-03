# Data source for Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security Group for NAT Instance
resource "aws_security_group" "nat_instance" {
  name        = "sentinel-nat-instance-sg"
  description = "Security group for NAT instance"
  vpc_id      = aws_vpc.sentinel.id

  # Allow inbound traffic from private subnet
  ingress {
    description = "Allow HTTP from private subnet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.2.0/24"]
  }

  ingress {
    description = "Allow HTTPS from private subnet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.2.0/24"]
  }

  ingress {
    description = "Allow all TCP from private subnet for NAT"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.2.0/24"]
  }

  ingress {
    description = "Allow SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Allow all outbound traffic
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "sentinel-nat-instance-sg"
    Project = "Sentinel Network"
  }
}

# Elastic IP for NAT Instance
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name    = "sentinel-nat-eip"
    Project = "Sentinel Network"
  }

  depends_on = [aws_internet_gateway.sentinel]
}

# NAT Instance
resource "aws_instance" "nat" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.nat_instance.id]
  associate_public_ip_address = true
  source_dest_check           = false

  user_data = <<-EOF
              #!/bin/bash
              # Enable IP forwarding
              echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
              sysctl -p
              
              # Configure iptables for NAT
              yum install -y iptables-services
              systemctl enable iptables
              systemctl start iptables
              
              # Set up NAT rules
              iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
              iptables -A FORWARD -i eth0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
              iptables -A FORWARD -i eth0 -o eth0 -j ACCEPT
              
              # Save iptables rules
              service iptables save
              EOF

  tags = {
    Name    = "sentinel-nat-instance"
    Project = "Sentinel Network"
    Role    = "nat"
  }
}

# Associate Elastic IP with NAT Instance
resource "aws_eip_association" "nat" {
  instance_id   = aws_instance.nat.id
  allocation_id = aws_eip.nat.id
}

# Route for Private Subnet through NAT Instance
resource "aws_route" "private_nat_instance" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}