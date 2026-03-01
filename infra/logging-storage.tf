resource "aws_cloudwatch_log_group" "vpc_flow" {
  name              = "/sentinel/vpc-flow"
  retention_in_days = 30

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-vpc-flow-logs"
    }
  )
}

resource "aws_cloudwatch_log_group" "system" {
  name              = "/sentinel/system"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "nginx" {
  name              = "/sentinel/system/nginx"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "watcher" {
  name              = "/sentinel/watcher"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "proxy" {
  name              = "/sentinel/blockchain-proxy"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "cloud_init" {
  name              = "/sentinel/cloud-init"
  retention_in_days = 30
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "SentinelVpcFlowLogsRole"

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
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "SentinelVpcFlowLogsPolicy"
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
  log_group_name       = aws_cloudwatch_log_group.vpc_flow.name
  iam_role_arn         = aws_iam_role.vpc_flow_logs.arn

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-vpc-flow-logs"
    }
  )
}

resource "aws_cloudwatch_log_metric_filter" "watcher_processed_block" {
  name           = "sentinel-watcher-processed-block"
  log_group_name = aws_cloudwatch_log_group.watcher.name
  pattern        = "Processed block"

  metric_transformation {
    name      = "WatcherProcessedBlock"
    namespace = "Sentinel/Monitoring"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "watcher_silent" {
  alarm_name          = "sentinel-watcher-silent-10min"
  alarm_description   = "Watcher has not processed any blocks in the last 10 minutes"
  namespace           = "Sentinel/Monitoring"
  metric_name         = "WatcherProcessedBlock"
  statistic           = "Sum"
  period              = 600
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
}

resource "aws_cloudwatch_log_metric_filter" "nginx_rate_limit" {
  name           = "sentinel-nginx-429"
  log_group_name = aws_cloudwatch_log_group.nginx.name
  pattern        = "\" 429 \""

  metric_transformation {
    name      = "NginxRateLimited"
    namespace = "Sentinel/Monitoring"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "nginx_rate_limit" {
  alarm_name          = "sentinel-nginx-rate-limit"
  alarm_description   = "NGINX 429 rate limit responses detected"
  namespace           = "Sentinel/Monitoring"
  metric_name         = "NginxRateLimited"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 20
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_log_metric_filter" "ipfs_unhealthy" {
  name           = "sentinel-ipfs-unhealthy"
  log_group_name = aws_cloudwatch_log_group.system.name
  pattern        = "ipfs-node.service Failed"

  metric_transformation {
    name      = "IpfsUnhealthy"
    namespace = "Sentinel/Monitoring"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "ipfs_unhealthy" {
  alarm_name          = "sentinel-ipfs-unhealthy"
  alarm_description   = "IPFS systemd service failure detected"
  namespace           = "Sentinel/Monitoring"
  metric_name         = "IpfsUnhealthy"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_s3_bucket" "events" {
  bucket        = "sentinel-events-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-events"
    }
  )
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
    Statement = [
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
    ]
  })
}
