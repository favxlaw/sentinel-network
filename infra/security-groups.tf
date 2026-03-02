resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = aws_vpc.sentinel.id

  ingress {
    description = "SSH from anywhere"
    from_port   = var.ssh_port
    to_port     = var.ssh_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-bastion-sg"
      Role = "bastion"
    }
  )
}

resource "aws_security_group" "nginx" {
  name        = "${var.project_name}-nginx-sg"
  description = "Security group for NGINX gateway"
  vpc_id      = aws_vpc.sentinel.id

  ingress {
    description = "HTTP from internet"
    from_port   = var.http_port
    to_port     = var.http_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = var.https_port
    to_port     = var.https_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description     = "SSH from bastion"
    from_port       = var.ssh_port
    to_port         = var.ssh_port
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-nginx-sg"
      Role = "nginx"
    }
  )
}

resource "aws_security_group" "blockchain_proxy" {
  name        = "${var.project_name}-blockchain-proxy-sg"
  description = "Security group for blockchain proxy service"
  vpc_id      = aws_vpc.sentinel.id

  ingress {
    description     = "JSON-RPC from NGINX"
    from_port       = var.ethereum_rpc_port
    to_port         = var.ethereum_rpc_port
    protocol        = "tcp"
    security_groups = [aws_security_group.nginx.id]
  }

  ingress {
    description     = "JSON-RPC from watcher"
    from_port       = var.ethereum_rpc_port
    to_port         = var.ethereum_rpc_port
    protocol        = "tcp"
    security_groups = [aws_security_group.watcher.id]
  }

  ingress {
    description     = "SSH from bastion"
    from_port       = var.ssh_port
    to_port         = var.ssh_port
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-blockchain-proxy-sg"
      Role = "blockchain-proxy"
    }
  )
}

# Watcher Service Security Group
resource "aws_security_group" "watcher" {
  name        = "${var.project_name}-watcher-sg"
  description = "Security group for watcher service"
  vpc_id      = aws_vpc.sentinel.id

  ingress {
    description     = "SSH from bastion"
    from_port       = var.ssh_port
    to_port         = var.ssh_port
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description     = "Health check from aggregator"
    from_port       = var.watcher_health_port
    to_port         = var.watcher_health_port
    protocol        = "tcp"
    security_groups = [aws_security_group.aggregator.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-watcher-sg"
      Role = "watcher"
    }
  )
}

# IPFS Security Group
resource "aws_security_group" "ipfs" {
  name        = "${var.project_name}-ipfs-sg"
  description = "Security group for IPFS node"
  vpc_id      = aws_vpc.sentinel.id

  ingress {
    description     = "IPFS API from watcher"
    from_port       = var.ipfs_api_port
    to_port         = var.ipfs_api_port
    protocol        = "tcp"
    security_groups = [aws_security_group.watcher.id]
  }

  ingress {
    description     = "IPFS API from aggregator"
    from_port       = var.ipfs_api_port
    to_port         = var.ipfs_api_port
    protocol        = "tcp"
    security_groups = [aws_security_group.aggregator.id]
  }

  ingress {
    description     = "IPFS Gateway from aggregator"
    from_port       = var.ipfs_gateway_port
    to_port         = var.ipfs_gateway_port
    protocol        = "tcp"
    security_groups = [aws_security_group.aggregator.id]
  }

  ingress {
    description     = "SSH from bastion"
    from_port       = var.ssh_port
    to_port         = var.ssh_port
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-ipfs-sg"
      Role = "ipfs"
    }
  )
}

# Aggregator API Security Group
resource "aws_security_group" "aggregator" {
  name        = "${var.project_name}-aggregator-sg"
  description = "Security group for aggregator API"
  vpc_id      = aws_vpc.sentinel.id

  ingress {
    description     = "FastAPI from NGINX"
    from_port       = var.fastapi_port
    to_port         = var.fastapi_port
    protocol        = "tcp"
    security_groups = [aws_security_group.nginx.id]
  }

  ingress {
    description     = "SSH from bastion"
    from_port       = var.ssh_port
    to_port         = var.ssh_port
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-aggregator-sg"
      Role = "aggregator"
    }
  )
}

# Tenant Security Groups - Dynamic creation based on var.tenants
resource "aws_security_group" "tenant" {
  for_each = { for tenant in var.tenants : tenant.id => tenant }

  name        = "${var.project_name}-tenant-${each.value.id}-sg"
  description = "Security group for ${each.value.id} tenant"
  vpc_id      = aws_vpc.sentinel.id

  ingress {
    description     = "HTTPS from NGINX for ${each.value.id}"
    from_port       = var.https_port
    to_port         = var.https_port
    protocol        = "tcp"
    security_groups = [aws_security_group.nginx.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.common_tags,
    {
      Name   = "${var.project_name}-tenant-${each.value.id}-sg"
      Tenant = each.value.id
    }
  )
}