output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.sentinel.id
}

output "public_subnet_id" {
  description = "Public subnet ID"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "Private subnet ID"
  value       = aws_subnet.private.id
}

output "bastion_public_ip" {
  description = "Public IP of bastion host"
  value       = aws_instance.bastion.public_ip
}

output "bastion_instance_id" {
  description = "Instance ID of bastion host"
  value       = aws_instance.bastion.id
}

output "nat_instance_public_ip" {
  description = "Public IP (Elastic IP) of NAT instance"
  value       = aws_eip.nat.public_ip
}

output "nat_instance_id" {
  description = "Instance ID of NAT instance"
  value       = aws_instance.nat.id
}

output "ipfs_private_ip" {
  description = "Private IP of IPFS node"
  value       = aws_instance.ipfs.private_ip
}

output "ipfs_instance_id" {
  description = "Instance ID of IPFS node"
  value       = aws_instance.ipfs.id
}

output "ipfs_availability_zone" {
  description = "Availability zone of IPFS node"
  value       = aws_instance.ipfs.availability_zone
}

output "security_groups" {
  description = "Map of created security groups"
  value = {
    bastion          = aws_security_group.bastion.id
    nat              = aws_security_group.nat_instance.id
    ipfs             = aws_security_group.ipfs.id
    blockchain_proxy = aws_security_group.blockchain_proxy.id
    watcher          = aws_security_group.watcher.id
    aggregator       = aws_security_group.aggregator.id
  }
}