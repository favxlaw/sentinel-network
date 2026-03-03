############################################
# CloudWatch Log Groups
############################################

# Required by spec: /sentinel/tenant/{id}/events
resource "aws_cloudwatch_log_group" "tenant_events" {
  for_each          = toset(var.tenant_ids)
  name              = "/sentinel/tenant/${each.key}/events"
  retention_in_days = 30

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-tenant-${each.key}-events"
  })
}

# Required by spec: /sentinel/system/nginx
resource "aws_cloudwatch_log_group" "nginx" {
  name              = "/sentinel/system/nginx"
  retention_in_days = 30

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-nginx-logs"
  })
}

resource "aws_cloudwatch_log_group" "watcher" {
  name              = "/sentinel/watcher"
  retention_in_days = 30

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-watcher-logs"
  })
}

resource "aws_cloudwatch_log_group" "proxy" {
  name              = "/sentinel/blockchain-proxy"
  retention_in_days = 30

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-proxy-logs"
  })
}

resource "aws_cloudwatch_log_group" "system" {
  name              = "/sentinel/system"
  retention_in_days = 30

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-system-logs"
  })
}

resource "aws_cloudwatch_log_group" "vpc_flow" {
  name              = "/sentinel/vpc-flow"
  retention_in_days = 30

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpc-flow-logs"
  })
}

resource "aws_cloudwatch_log_group" "cloud_init" {
  name              = "/sentinel/cloud-init"
  retention_in_days = 30

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-cloud-init-logs"
  })
}

############################################
# VPC Flow Logs
############################################

resource "aws_iam_role" "vpc_flow_logs" {
  name = "${var.project_name}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpc-flow-logs-role"
  })
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "${var.project_name}-vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          aws_cloudwatch_log_group.vpc_flow.arn,
          "${aws_cloudwatch_log_group.vpc_flow.arn}:*"
        ]
      }
    ]
  })
}

resource "aws_flow_log" "vpc" {
  vpc_id               = aws_vpc.sentinel.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.vpc_flow.arn
  iam_role_arn         = aws_iam_role.vpc_flow_logs.arn

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpc-flow-logs"
  })
}

############################################
# Alarm: Watcher silent > 10 minutes
############################################

resource "aws_cloudwatch_log_metric_filter" "watcher_processed_block" {
  name           = "${var.project_name}-watcher-processed-block"
  log_group_name = aws_cloudwatch_log_group.watcher.name
  pattern        = "Processed block"

  metric_transformation {
    name      = "WatcherProcessedBlock"
    namespace = var.cloudwatch_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "watcher_silent" {
  alarm_name          = "${var.project_name}-watcher-silent-10min"
  alarm_description   = "Watcher has not processed any blocks in the last 10 minutes"
  namespace           = var.cloudwatch_namespace
  metric_name         = "WatcherProcessedBlock"
  statistic           = "Sum"
  period              = 600
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-watcher-silent-alarm"
  })
}

############################################
# Alarm: NGINX rate limit > 80% per tenant
############################################

resource "aws_cloudwatch_log_metric_filter" "nginx_rate_limit" {
  name           = "${var.project_name}-nginx-429"
  log_group_name = aws_cloudwatch_log_group.nginx.name
  pattern        = "\" 429 \""

  metric_transformation {
    name      = "NginxRateLimited"
    namespace = var.cloudwatch_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "nginx_rate_limit" {
  for_each = var.tenant_rate_limits

  alarm_name          = "${var.project_name}-nginx-rate-limit-${each.key}"
  alarm_description   = "NGINX rate limit for ${each.key} exceeded 80% (${each.value} req/min)"
  namespace           = var.cloudwatch_namespace
  metric_name         = "NginxRateLimited"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = each.value
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  tags = merge(var.common_tags, {
    Name   = "${var.project_name}-nginx-rate-limit-${each.key}"
    Tenant = each.key
  })
}

############################################
# Alarm: IPFS unhealthy
############################################

resource "aws_cloudwatch_log_metric_filter" "ipfs_unhealthy" {
  name           = "${var.project_name}-ipfs-unhealthy"
  log_group_name = aws_cloudwatch_log_group.system.name
  pattern        = "ipfs-node.service Failed"

  metric_transformation {
    name      = "IpfsUnhealthy"
    namespace = var.cloudwatch_namespace
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "ipfs_unhealthy" {
  alarm_name          = "${var.project_name}-ipfs-unhealthy"
  alarm_description   = "IPFS systemd service failure detected"
  namespace           = var.cloudwatch_namespace
  metric_name         = "IpfsUnhealthy"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-ipfs-unhealthy-alarm"
  })
}

############################################
# S3 Bucket for Events
############################################

resource "aws_s3_bucket" "events" {
  bucket        = "${var.project_name}-events-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-events"
  })
}

resource "aws_s3_bucket_public_access_block" "events" {
  bucket = aws_s3_bucket.events.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "events" {
  bucket = aws_s3_bucket.events.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "events" {
  bucket = aws_s3_bucket.events.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "events" {
  bucket = aws_s3_bucket.events.id

  rule {
    id     = "glacier-after-30-days"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "GLACIER"
    }
  }
}

resource "aws_s3_bucket_policy" "events" {
  bucket = aws_s3_bucket.events.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid       = "DenyNonSSLRequests"
          Effect    = "Deny"
          Principal = "*"
          Action    = "s3:*"
          Resource = [
            aws_s3_bucket.events.arn,
            "${aws_s3_bucket.events.arn}/*"
          ]
          Condition = {
            Bool = {
              "aws:SecureTransport" = "false"
            }
          }
        },
        {
          Sid       = "DenyUnencryptedObjectUploads"
          Effect    = "Deny"
          Principal = "*"
          Action    = "s3:PutObject"
          Resource  = "${aws_s3_bucket.events.arn}/*"
          Condition = {
            StringNotEquals = {
              "s3:x-amz-server-side-encryption" = "AES256"
            }
          }
        }
      ],
      [
        for tenant_id in var.tenant_ids : {
          Sid    = "TenantScopedAccess${replace(tenant_id, "-", "")}"
          Effect = "Allow"
          Principal = {
            AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${aws_iam_role.backend.name}"
          }
          Action = [
            "s3:PutObject",
            "s3:GetObject"
          ]
          Resource = "${aws_s3_bucket.events.arn}/${tenant_id}/*"
        }
      ]
    )
  })
}