# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# Local variables for reusable values
locals {
  account_id = var.aws_account_id != "" ? var.aws_account_id : data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name

  # Log group ARNs
  system_log_group_arn = "arn:aws:logs:${local.region}:${local.account_id}:log-group:${var.log_group_prefix}/system/*"
  tenant_log_groups = [
    for tenant in var.tenants :
    "arn:aws:logs:${local.region}:${local.account_id}:log-group:${var.log_group_prefix}/tenant/${tenant.id}/*"
  ]

  # S3 bucket ARN
  s3_bucket_arn = "arn:aws:s3:::${var.s3_bucket_prefix}-*"
}

# IAM Role for Bastion Host
resource "aws_iam_role" "bastion" {
  name = "${var.project_name}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-bastion-role"
      Role = "bastion"
    }
  )
}

resource "aws_iam_role_policy" "bastion_policy" {
  name = "${var.project_name}-bastion-policy"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.project_name}-bastion-profile"
  role = aws_iam_role.bastion.name

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-bastion-profile"
    }
  )
}

# IAM Role for Blockchain Proxy
resource "aws_iam_role" "blockchain_proxy" {
  name = "${var.project_name}-blockchain-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-blockchain-proxy-role"
      Role = "blockchain-proxy"
    }
  )
}

resource "aws_iam_role_policy" "blockchain_proxy_policy" {
  name = "${var.project_name}-blockchain-proxy-policy"
  role = aws_iam_role.blockchain_proxy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = local.system_log_group_arn
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "blockchain_proxy" {
  name = "${var.project_name}-blockchain-proxy-profile"
  role = aws_iam_role.blockchain_proxy.name

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-blockchain-proxy-profile"
    }
  )
}

# IAM Role for Watcher Service
resource "aws_iam_role" "watcher" {
  name = "${var.project_name}-watcher-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-watcher-role"
      Role = "watcher"
    }
  )
}

resource "aws_iam_role_policy" "watcher_policy" {
  name = "${var.project_name}-watcher-policy"
  role = aws_iam_role.watcher.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = local.tenant_log_groups
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          "${local.s3_bucket_arn}",
          "${local.s3_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "watcher" {
  name = "${var.project_name}-watcher-profile"
  role = aws_iam_role.watcher.name

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-watcher-profile"
    }
  )
}

# IAM Role for IPFS Node
resource "aws_iam_role" "ipfs" {
  name = "${var.project_name}-ipfs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-ipfs-role"
      Role = "ipfs"
    }
  )
}

resource "aws_iam_role_policy" "ipfs_policy" {
  name = "${var.project_name}-ipfs-policy"
  role = aws_iam_role.ipfs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "${var.log_group_prefix}/system/ipfs/*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ipfs" {
  name = "${var.project_name}-ipfs-profile"
  role = aws_iam_role.ipfs.name

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-ipfs-profile"
    }
  )
}

# IAM Role for Aggregator API
resource "aws_iam_role" "aggregator" {
  name = "${var.project_name}-aggregator-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-aggregator-role"
      Role = "aggregator"
    }
  )
}

resource "aws_iam_role_policy" "aggregator_policy" {
  name = "${var.project_name}-aggregator-policy"
  role = aws_iam_role.aggregator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = concat(
          local.tenant_log_groups,
          ["${local.system_log_group_arn}"]
        )
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          local.s3_bucket_arn,
          "${local.s3_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "aggregator" {
  name = "${var.project_name}-aggregator-profile"
  role = aws_iam_role.aggregator.name

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-aggregator-profile"
    }
  )
}

# IAM Role for NGINX Gateway
resource "aws_iam_role" "nginx" {
  name = "${var.project_name}-nginx-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-nginx-role"
      Role = "nginx"
    }
  )
}

resource "aws_iam_role_policy" "nginx_policy" {
  name = "${var.project_name}-nginx-policy"
  role = aws_iam_role.nginx.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "${var.log_group_prefix}/system/nginx/*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "nginx" {
  name = "${var.project_name}-nginx-profile"
  role = aws_iam_role.nginx.name

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-nginx-profile"
    }
  )
}