terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu_2204" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "sentinel" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-vpc"
    }
  )
}

resource "aws_internet_gateway" "sentinel" {
  vpc_id = aws_vpc.sentinel.id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-igw"
    }
  )
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.sentinel.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-public-subnet"
      Type = "public"
    }
  )
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.sentinel.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-private-subnet"
      Type = "private"
    }
  )
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.sentinel.id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-public-rt"
    }
  )
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.sentinel.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.sentinel.id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-private-rt"
    }
  )
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# Bastion + NAT instance (public)
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.ubuntu_2204.id
  instance_type          = var.bastion_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.bastion.id, aws_security_group.nat.id]
  key_name               = var.key_name
  private_ip             = "10.0.1.10"

  associate_public_ip_address = true
  source_dest_check           = false

  user_data                   = file("${path.module}/user-data/bastion.sh")
  user_data_replace_on_change = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-bastion-nat"
      Role = "bastion-nat"
    }
  )

  depends_on = [aws_internet_gateway.sentinel]
}

resource "aws_eip" "bastion" {
  domain = "vpc"

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-bastion-eip"
      Role = "bastion-nat"
    }
  )

  depends_on = [aws_internet_gateway.sentinel]
}

resource "aws_eip_association" "bastion" {
  instance_id   = aws_instance.bastion.id
  allocation_id = aws_eip.bastion.id
}

# NGINX gateway (public)
resource "aws_instance" "nginx" {
  ami                    = data.aws_ami.ubuntu_2204.id
  instance_type          = var.nginx_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.nginx.id]
  key_name               = var.key_name
  private_ip             = "10.0.1.30"

  associate_public_ip_address = true

  user_data                   = file("${path.module}/user-data/nginx.sh")
  user_data_replace_on_change = true

  iam_instance_profile = aws_iam_instance_profile.nginx.name

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-nginx"
      Role = "nginx"
    }
  )

  depends_on = [aws_internet_gateway.sentinel]
}

resource "aws_eip" "nginx" {
  domain = "vpc"

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-nginx-eip"
      Role = "nginx"
    }
  )

  depends_on = [aws_internet_gateway.sentinel]
}

resource "aws_eip_association" "nginx" {
  instance_id   = aws_instance.nginx.id
  allocation_id = aws_eip.nginx.id
}

# Backend instance (private)
resource "aws_instance" "backend" {
  ami                    = data.aws_ami.ubuntu_2204.id
  instance_type          = var.backend_instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [
    aws_security_group.proxy.id,
    aws_security_group.watcher.id,
    aws_security_group.ipfs.id,
    aws_security_group.aggregator.id
  ]
  key_name               = var.key_name

  associate_public_ip_address = false

  iam_instance_profile = aws_iam_instance_profile.backend.name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = true
  }

  ebs_block_device {
    device_name           = "/dev/sdf"
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
  }

  user_data                   = file("${path.module}/user-data/backend.sh")
  user_data_replace_on_change = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-backend"
      Role = "backend"
    }
  )

  depends_on = [aws_route.private_nat_instance]
}

# Private route to NAT instance (bastion)
resource "aws_route" "private_nat_instance" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.bastion.primary_network_interface_id
}
