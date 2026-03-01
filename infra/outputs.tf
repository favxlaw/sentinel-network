output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.sentinel.id
}

output "bastion_public_ip" {
  description = "Public IP of bastion host"
  value       = aws_eip.bastion.public_ip
}

output "nat_public_ip" {
  description = "Public IP of NAT instance"
  value       = aws_eip.nat.public_ip
}

output "nginx_public_ip" {
  description = "Public IP of NGINX gateway"
  value       = aws_eip.nginx.public_ip
}

output "backend_private_ip" {
  description = "Private IP of backend instance"
  value       = aws_instance.backend.private_ip
}

output "events_bucket_name" {
  description = "S3 bucket for tenant event archives"
  value       = aws_s3_bucket.events.bucket
}

output "vpc_flow_log_group" {
  description = "CloudWatch log group for VPC Flow Logs"
  value       = aws_cloudwatch_log_group.vpc_flow.name
}
