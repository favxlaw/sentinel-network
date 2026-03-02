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

resource "aws_security_group" "nat_instance" {
  name        = "${var.project_name}-nat-instance-sg"
  description = "Security group for NAT instance"
  vpc_id      = aws_vpc.sentinel.id

  ingress {
    description = "Allow HTTP from private subnet"
    from_port   = var.http_port
    to_port     = var.http_port
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_cidr]
  }

  ingress {
    description = "Allow HTTPS from private subnet"
    from_port   = var.https_port
    to_port     = var.https_port
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_cidr]
  }

  ingress {
    description = "Allow all TCP from private subnet for NAT"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_cidr]
  }

  ingress {
    description = "Allow SSH from VPC"
    from_port   = var.ssh_port
    to_port     = var.ssh_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-nat-instance-sg"
      Role = "nat"
    }
  )
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-nat-eip"
      Role = "nat"
    }
  )

  depends_on = [aws_internet_gateway.sentinel]
}

resource "aws_instance" "nat" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = var.nat_instance_type
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

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-nat-instance"
      Role = "nat"
    }
  )
}

resource "aws_eip_association" "nat" {
  instance_id   = aws_instance.nat.id
  allocation_id = aws_eip.nat.id
}

resource "aws_route" "private_nat_instance" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}