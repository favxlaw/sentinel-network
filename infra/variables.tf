# Core configuration
variable "project_name" {
  default = "sentinel"
  type        = string
}

variable "common_tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {}
}

variable "tenant_ids" {
  description = "Tenant identifiers used for scoping access"
  type        = list(string)
  default     = ["dao-alpha", "dao-beta", "dao-gamma"]
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "admin_ip" {
  description = "Admin public IP CIDR for SSH access (e.g., 203.0.113.10/32)"
  type        = string
}

variable "key_name" {
  default = "sentinel-keypair"
  type        = string
}

# Network configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnet"
  type        = string
  default     = "10.0.10.0/24"
}

variable "availability_zone" {
  description = "Availability zone for subnets"
  type        = string
  default     = "us-east-1a"
}

# Instance configuration
variable "bastion_instance_type" {
  description = "EC2 instance type for bastion host"
  type        = string
  default     = "t2.micro"
}

variable "nat_instance_type" {
  description = "EC2 instance type for NAT instance"
  type        = string
  default     = "t2.micro"
}

variable "nginx_instance_type" {
  description = "EC2 instance type for NGINX gateway"
  type        = string
  default     = "t2.micro"
}

variable "backend_instance_type" {
  description = "EC2 instance type for backend (proxy+watcher+ipfs+aggregator)"
  type        = string
  default     = "t2.small"
}

# Service ports
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
  description = "Aggregator API port"
  type        = number
  default     = 8006
}

variable "ipfs_api_port" {
  description = "IPFS API port"
  type        = number
  default     = 5001
}

variable "cloudwatch_namespace" {
  description = "CloudWatch namespace for all Sentinel metrics"
  type        = string
  default     = "Sentinel/Monitoring"
}

variable "tenant_rate_limits" {
  description = "Per-tenant NGINX rate limit 80% thresholds (requests per minute)"
  type        = map(number)
  default = {
    "dao-alpha" = 80
    "dao-beta"  = 40
    "dao-gamma" = 160
  }
}

variable "base_domain" {
  description = "Base domain for NGINX virtual hosting"
  type        = string
  default     = "sentinel.local"
}


