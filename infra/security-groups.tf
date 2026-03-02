resource "aws_security_group" "bastion" {
  name        = "sg-bastion-sentinel"
  description = "Bastion host security group"
  vpc_id      = aws_vpc.sentinel.id

  ingress {
    description = "SSH from admin IP"
    from_port   = var.ssh_port
    to_port     = var.ssh_port
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }

  egress {
    description = "SSH to private subnet"
    from_port   = var.ssh_port
    to_port     = var.ssh_port
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_cidr]
  }

  tags = merge(
    var.common_tags,
    {
      Name = "sg-bastion-sentinel"
    }
  )
}

resource "aws_security_group" "nat" {
  name        = "sg-nat-sentinel"
  description = "NAT instance security group"
  vpc_id      = aws_vpc.sentinel.id

  ingress {
    description = "All traffic from private subnet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.private_subnet_cidr]
  }

  egress {
    description = "HTTP to internet"
    from_port   = var.http_port
    to_port     = var.http_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTPS to internet"
    from_port   = var.https_port
    to_port     = var.https_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.common_tags,
    {
      Name = "sg-nat-sentinel"
    }
  )
}

resource "aws_security_group" "nginx" {
  name        = "sg-nginx-sentinel"
  description = "NGINX gateway security group"
  vpc_id      = aws_vpc.sentinel.id

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
    description     = "Aggregator API"
    from_port       = var.fastapi_port
    to_port         = var.fastapi_port
    protocol        = "tcp"
    security_groups = [aws_security_group.aggregator.id]
  }

  tags = merge(
    var.common_tags,
    {
      Name = "sg-nginx-sentinel"
    }
  )
}

resource "aws_security_group" "proxy" {
  name        = "sg-proxy-sentinel"
  description = "Blockchain proxy security group"
  vpc_id      = aws_vpc.sentinel.id

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
    description = "HTTPS to internet via NAT"
    from_port   = var.https_port
    to_port     = var.https_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.common_tags,
    {
      Name = "sg-proxy-sentinel"
    }
  )
}

resource "aws_security_group" "watcher" {
  name        = "sg-watcher-sentinel"
  description = "Watcher security group"
  vpc_id      = aws_vpc.sentinel.id

  ingress {
    description     = "SSH from bastion"
    from_port       = var.ssh_port
    to_port         = var.ssh_port
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    description     = "JSON-RPC to proxy"
    from_port       = var.ethereum_rpc_port
    to_port         = var.ethereum_rpc_port
    protocol        = "tcp"
    security_groups = [aws_security_group.proxy.id]
  }

  egress {
    description     = "IPFS API to IPFS"
    from_port       = var.ipfs_api_port
    to_port         = var.ipfs_api_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ipfs.id]
  }

  tags = merge(
    var.common_tags,
    {
      Name = "sg-watcher-sentinel"
    }
  )
}

resource "aws_security_group" "ipfs" {
  name        = "sg-ipfs-sentinel"
  description = "IPFS security group"
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
    description     = "SSH from bastion"
    from_port       = var.ssh_port
    to_port         = var.ssh_port
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress = []

  tags = merge(
    var.common_tags,
    {
      Name = "sg-ipfs-sentinel"
    }
  )
}

resource "aws_security_group" "aggregator" {
  name        = "sg-aggregator-sentinel"
  description = "Aggregator security group"
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
    description     = "IPFS API to IPFS"
    from_port       = var.ipfs_api_port
    to_port         = var.ipfs_api_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ipfs.id]
  }

  tags = merge(
    var.common_tags,
    {
      Name = "sg-aggregator-sentinel"
    }
  )
}
