output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.sentinel.id
}

output "bastion_public_ip" {
  description = "Public IP of bastion host"
  value       = aws_eip.bastion.public_ip
}

output "nginx_public_ip" {
  description = "Public IP of NGINX gateway"
  value       = aws_eip.nginx.public_ip
}

output "backend_private_ip" {
  description = "Private IP of backend instance"
  value       = aws_instance.backend.private_ip
}
