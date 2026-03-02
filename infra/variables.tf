# AWS Region
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# Project Configuration
variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "sentinel"
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "Sentinel Network"
    ManagedBy   = "Terraform"
    Environment = "production"
  }
}

# Network Configuration
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

# Instance Configuration
variable "nat_instance_type" {
  description = "EC2 instance type for NAT instance"
  type        = string
  default     = "t2.micro"
}

variable "bastion_instance_type" {
  description = "EC2 instance type for bastion host"
  type        = string
  default     = "t2.micro"
}

variable "ipfs_instance_type" {
  description = "EC2 instance type for IPFS node"
  type        = string
  default     = "t3.medium"
}

variable "ipfs_root_volume_size" {
  description = "Root volume size in GB for IPFS instance"
  type        = number
  default     = 30
}

variable "ipfs_data_volume_size" {
  description = "Data volume size in GB for IPFS"
  type        = number
  default     = 100
}

# IPFS Configuration
variable "ipfs_version" {
  description = "IPFS Kubo version to install"
  type        = string
  default     = "v0.25.0"
}

variable "ipfs_path" {
  description = "IPFS repository path on the instance"
  type        = string
  default     = "/opt/sentinel/ipfs"
}

variable "ipfs_api_bind_address" {
  description = "IPFS API bind address"
  type        = string
  default     = "/ip4/127.0.0.1/tcp/5001"
}

variable "ipfs_gateway_bind_address" {
  description = "IPFS Gateway bind address"
  type        = string
  default     = "/ip4/127.0.0.1/tcp/8080"
}

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

# Tenant Configuration
variable "tenants" {
  description = "List of tenants with their configurations"
  type = list(object({
    id = string
  }))
  default = []
}