# Add these to your existing variables.tf file

# Service Ports
variable "ssh_port" {
  description = "SSH port"
  type        = number
  default     = 22
}

variable "http_port" {
  description = "HTTP port"
  type        = number
  default     = 80
}

variable "https_port" {
  description = "HTTPS port"
  type        = number
  default     = 443
}

variable "ethereum_rpc_port" {
  description = "Ethereum JSON-RPC port"
  type        = number
  default     = 8545
}

variable "fastapi_port" {
  description = "FastAPI service port"
  type        = number
  default     = 8000
}

variable "ipfs_api_port" {
  description = "IPFS API port"
  type        = number
  default     = 5001
}

variable "ipfs_gateway_port" {
  description = "IPFS Gateway port"
  type        = number
  default     = 8080
}

variable "watcher_health_port" {
  description = "Watcher service health check port"
  type        = number
  default     = 8080
}

# S3 Configuration
variable "s3_bucket_prefix" {
  description = "Prefix for S3 bucket names"
  type        = string
  default     = "sentinel-events"
}

# CloudWatch Log Groups
variable "log_group_prefix" {
  description = "Prefix for CloudWatch log groups"
  type        = string
  default     = "/sentinel"
}

# AWS Account (will be fetched dynamically)
variable "aws_account_id" {
  description = "AWS Account ID (leave empty to auto-detect)"
  type        = string
  default     = ""
}