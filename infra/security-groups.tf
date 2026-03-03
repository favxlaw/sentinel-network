############################################
# Bastion Security Group
############################################

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

  egress {
    description = "HTTPS to internet for SSM and outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP to internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "ICMP to public subnet for reachability checks"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.public_subnet_cidr]
  }

  tags = merge(var.common_tags, {
    Name = "sg-bastion-sentinel"
  })
}

############################################
# NAT Security Group
############################################

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

  ingress {
    description = "ICMP from public subnet"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.public_subnet_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "sg-nat-sentinel"
  })
}

############################################
# Service Security Groups
############################################

resource "aws_security_group" "nginx" {
  name        = "sentinel-nginx-sg"
  description = "NGINX gateway security group"
  vpc_id      = aws_vpc.sentinel.id

  tags = merge(var.common_tags, {
    Name = "sg-nginx-sentinel"
  })
}

resource "aws_security_group" "proxy" {
  name        = "sentinel-proxy-sg"
  description = "Blockchain proxy security group"
  vpc_id      = aws_vpc.sentinel.id

  tags = merge(var.common_tags, {
    Name = "sg-proxy-sentinel"
  })
}

resource "aws_security_group" "watcher" {
  name        = "sentinel-watcher-sg"
  description = "Watcher security group"
  vpc_id      = aws_vpc.sentinel.id

  tags = merge(var.common_tags, {
    Name = "sg-watcher-sentinel"
  })
}

resource "aws_security_group" "ipfs" {
  name        = "sentinel-ipfs-sg"
  description = "IPFS security group"
  vpc_id      = aws_vpc.sentinel.id

  tags = merge(var.common_tags, {
    Name = "sg-ipfs-sentinel"
  })
}

resource "aws_security_group" "aggregator" {
  name        = "sentinel-aggregator-sg"
  description = "Aggregator security group"
  vpc_id      = aws_vpc.sentinel.id

  tags = merge(var.common_tags, {
    Name = "sg-aggregator-sentinel"
  })
}

resource "aws_security_group" "tenant" {
  for_each    = toset(var.tenant_ids)
  name        = "sentinel-${each.key}-sg"
  description = "Tenant security group for ${each.key}"
  vpc_id      = aws_vpc.sentinel.id

  tags = merge(var.common_tags, {
    Name   = "sg-${each.key}-sentinel"
    Tenant = each.key
  })
}

############################################
# NGINX Rules
############################################

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
  description       = "HTTPS to internet for SSM and outbound"
  from_port         = var.https_port
  to_port           = var.https_port
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

############################################
# Proxy Rules
############################################

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

resource "aws_security_group_rule" "proxy_http_out" {
  type              = "egress"
  security_group_id = aws_security_group.proxy.id
  description       = "HTTP to internet via NAT"
  from_port         = var.http_port
  to_port           = var.http_port
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
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

############################################
# Watcher Rules
############################################

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

resource "aws_security_group_rule" "watcher_https_out" {
  type              = "egress"
  security_group_id = aws_security_group.watcher.id
  description       = "HTTPS to internet via NAT for SSM and outbound"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "watcher_http_out" {
  type              = "egress"
  security_group_id = aws_security_group.watcher.id
  description       = "HTTP to internet via NAT"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

############################################
# IPFS Rules
############################################

resource "aws_security_group_rule" "ipfs_ssh_in" {
  type                     = "ingress"
  security_group_id        = aws_security_group.ipfs.id
  description              = "SSH from bastion"
  from_port                = var.ssh_port
  to_port                  = var.ssh_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
}

resource "aws_security_group_rule" "ipfs_api_in" {
  type                     = "ingress"
  security_group_id        = aws_security_group.ipfs.id
  description              = "IPFS API from aggregator"
  from_port                = var.ipfs_api_port
  to_port                  = var.ipfs_api_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.aggregator.id
}

resource "aws_security_group_rule" "ipfs_https_out" {
  type              = "egress"
  security_group_id = aws_security_group.ipfs.id
  description       = "HTTPS to internet via NAT for SSM and outbound"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "ipfs_http_out" {
  type              = "egress"
  security_group_id = aws_security_group.ipfs.id
  description       = "HTTP to internet via NAT"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

############################################
# Aggregator Rules
############################################

resource "aws_security_group_rule" "aggregator_ssh_in" {
  type                     = "ingress"
  security_group_id        = aws_security_group.aggregator.id
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

resource "aws_security_group_rule" "aggregator_ipfs_out" {
  type                     = "egress"
  security_group_id        = aws_security_group.aggregator.id
  description              = "IPFS API to ipfs SG"
  from_port                = var.ipfs_api_port
  to_port                  = var.ipfs_api_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ipfs.id
}

resource "aws_security_group_rule" "aggregator_https_out" {
  type              = "egress"
  security_group_id = aws_security_group.aggregator.id
  description       = "HTTPS to internet via NAT for SSM and outbound"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "aggregator_http_out" {
  type              = "egress"
  security_group_id = aws_security_group.aggregator.id
  description       = "HTTP to internet via NAT"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

############################################
# Tenant Rules
############################################

resource "aws_security_group_rule" "tenant_https_in" {
  for_each                 = aws_security_group.tenant
  type                     = "ingress"
  security_group_id        = each.value.id
  description              = "HTTPS from NGINX"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.nginx.id
}

resource "aws_security_group_rule" "tenant_fastapi_in" {
  for_each                 = aws_security_group.tenant
  type                     = "ingress"
  security_group_id        = each.value.id
  description              = "FastAPI from NGINX"
  from_port                = var.fastapi_port
  to_port                  = var.fastapi_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.nginx.id
}

resource "aws_security_group_rule" "tenant_all_out" {
  for_each          = aws_security_group.tenant
  type              = "egress"
  security_group_id = each.value.id
  description       = "Allow all outbound"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}
