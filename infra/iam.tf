data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

resource "aws_iam_role" "ops" {
  name = "SentinelOpsRole"

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
}

resource "aws_iam_role_policy_attachment" "ops_ssm_core" {
  role       = aws_iam_role.ops.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ops" {
  name = "SentinelOpsRole"
  role = aws_iam_role.ops.name
}

resource "aws_iam_role" "backend" {
  name = "SentinelBackendRole"

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
}

resource "aws_iam_role_policy" "backend" {
  name = "SentinelBackendPolicy"
  role = aws_iam_role.backend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/sentinel/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = [
          for tenant_id in var.tenant_ids :
          "arn:aws:s3:::sentinel-events-${local.account_id}/${tenant_id}/*"
        ]
        Condition = {
          StringEquals = {
            "s3:x-amz-server-side-encryption" = "AES256"
          }
        }
      },
      {
  Effect = "Allow"
  Action = ["cloudwatch:PutMetricData"]
  Resource = "*"
  Condition = {
    StringEquals = {
      "cloudwatch:namespace" = [
        "Sentinel/Monitoring",
        "Sentinel/Backend",
        "Sentinel/NAT",
        "Sentinel/NGINX",
        "Sentinel/Bastion",
        "CWAgent"
      ]
    }
  }
},
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:*:*:secret:sentinel/tenants/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "backend" {
  name = "SentinelBackendRole"
  role = aws_iam_role.backend.name
}

resource "aws_iam_role_policy_attachment" "backend_ssm_core" {
  role       = aws_iam_role.backend.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role" "nginx" {
  name = "SentinelNginxRole"

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
}

resource "aws_iam_role_policy" "nginx" {
  name = "SentinelNginxPolicy"
  role = aws_iam_role.nginx.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/sentinel/system/nginx*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "nginx" {
  name = "SentinelNginxRole"
  role = aws_iam_role.nginx.name
}

resource "aws_iam_role_policy_attachment" "nginx_ssm_core" {
  role       = aws_iam_role.nginx.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ops_cloudwatch" {
  role       = aws_iam_role.ops.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "backend_cloudwatch" {
  role       = aws_iam_role.backend.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "nginx_cloudwatch" {
  role       = aws_iam_role.nginx.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}