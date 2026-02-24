resource "aws_security_group" "bastion" {
  name        = "sentinel-bastion-sg"
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
  name        = "sentinel-nat-sg"
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
  name        = "sentinel-nginx-sg"
  description = "NGINX gateway security group"
  vpc_id      = aws_vpc.sentinel.id

  tags = merge(
    var.common_tags,
    {
      Name = "sg-nginx-sentinel"
    }
  )
}

resource "aws_security_group" "proxy" {
  name        = "sentinel-proxy-sg"
  description = "Blockchain proxy security group"
  vpc_id      = aws_vpc.sentinel.id

  tags = merge(
    var.common_tags,
    {
      Name = "sg-proxy-sentinel"
    }
  )
}

resource "aws_security_group" "watcher" {
  name        = "sentinel-watcher-sg"
  description = "Watcher security group"
  vpc_id      = aws_vpc.sentinel.id

  tags = merge(
    var.common_tags,
    {
      Name = "sg-watcher-sentinel"
    }
  )
}

resource "aws_security_group" "ipfs" {
  name        = "sentinel-ipfs-sg"
  description = "IPFS security group"
  vpc_id      = aws_vpc.sentinel.id

  tags = merge(
    var.common_tags,
    {
      Name = "sg-ipfs-sentinel"
    }
  )
}

resource "aws_security_group" "aggregator" {
  name        = "sentinel-aggregator-sg"
  description = "Aggregator security group"
  vpc_id      = aws_vpc.sentinel.id

  tags = merge(
    var.common_tags,
    {
      Name = "sg-aggregator-sentinel"
    }
  )
}

# ---- Security group rules (split to avoid cyclic dependencies) ----

resource "aws_security_group_rule" "nginx_https_in" {
  type              = "ingress"
  security_group_id = aws_security_group.nginx.id
  description       = "HTTPS from internet"
  from_port         = var.https_port
  to_port           = var.https_port
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "nginx_ssh_in" {
  type                     = "ingress"
  security_group_id        = aws_security_group.nginx.id
  description              = "SSH from bastion"
  from_port                = var.ssh_port
  to_port                  = var.ssh_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
}

resource "aws_security_group_rule" "nginx_fastapi_out" {
  type                     = "egress"
  security_group_id        = aws_security_group.nginx.id
  description              = "Aggregator API"
  from_port                = var.fastapi_port
  to_port                  = var.fastapi_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.aggregator.id
}

resource "aws_security_group_rule" "nginx_https_out" {
  type              = "egress"
  security_group_id = aws_security_group.nginx.id
  description       = "HTTPS to internet"
  from_port         = var.https_port
  to_port           = var.https_port
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "proxy_rpc_in" {
  type                     = "ingress"
  security_group_id        = aws_security_group.proxy.id
  description              = "JSON-RPC from watcher"
  from_port                = var.ethereum_rpc_port
  to_port                  = var.ethereum_rpc_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.watcher.id
}

resource "aws_security_group_rule" "proxy_ssh_in" {
  type                     = "ingress"
  security_group_id        = aws_security_group.proxy.id
  description              = "SSH from bastion"
  from_port                = var.ssh_port
  to_port                  = var.ssh_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
}

resource "aws_security_group_rule" "proxy_https_out" {
  type              = "egress"
  security_group_id = aws_security_group.proxy.id
  description       = "HTTPS to internet via NAT"
  from_port         = var.https_port
  to_port           = var.https_port
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "watcher_ssh_in" {
  type                     = "ingress"
  security_group_id        = aws_security_group.watcher.id
  description              = "SSH from bastion"
  from_port                = var.ssh_port
  to_port                  = var.ssh_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
}

resource "aws_security_group_rule" "watcher_rpc_out" {
  type                     = "egress"
  security_group_id        = aws_security_group.watcher.id
  description              = "JSON-RPC to proxy"
  from_port                = var.ethereum_rpc_port
  to_port                  = var.ethereum_rpc_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.proxy.id
}

resource "aws_security_group_rule" "watcher_ipfs_out" {
  type                     = "egress"
  security_group_id        = aws_security_group.watcher.id
  description              = "IPFS API to IPFS"
  from_port                = var.ipfs_api_port
  to_port                  = var.ipfs_api_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ipfs.id
}

resource "aws_security_group_rule" "ipfs_api_from_watcher_in" {
  type                     = "ingress"
  security_group_id        = aws_security_group.ipfs.id
  description              = "IPFS API from watcher"
  from_port                = var.ipfs_api_port
  to_port                  = var.ipfs_api_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.watcher.id
}

resource "aws_security_group_rule" "ipfs_api_from_aggregator_in" {
  type                     = "ingress"
  security_group_id        = aws_security_group.ipfs.id
  description              = "IPFS API from aggregator"
  from_port                = var.ipfs_api_port
  to_port                  = var.ipfs_api_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.aggregator.id
}

resource "aws_security_group_rule" "ipfs_ssh_in" {
  type                     = "ingress"
  security_group_id        = aws_security_group.ipfs.id
  description              = "SSH from bastion"
  from_port                = var.ssh_port
  to_port                  = var.ssh_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
}

resource "aws_security_group_rule" "aggregator_fastapi_in" {
  type                     = "ingress"
  security_group_id        = aws_security_group.aggregator.id
  description              = "FastAPI from NGINX"
  from_port                = var.fastapi_port
  to_port                  = var.fastapi_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.nginx.id
}

resource "aws_security_group_rule" "aggregator_ssh_in" {
  type                     = "ingress"
  security_group_id        = aws_security_group.aggregator.id
  description              = "SSH from bastion"
  from_port                = var.ssh_port
  to_port                  = var.ssh_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
}

resource "aws_security_group_rule" "aggregator_ipfs_out" {
  type                     = "egress"
  security_group_id        = aws_security_group.aggregator.id
  description              = "IPFS API to IPFS"
  from_port                = var.ipfs_api_port
  to_port                  = var.ipfs_api_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ipfs.id
}
