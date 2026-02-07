resource "aws_instance" "ipfs" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.ipfs_instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.ipfs.id]
  iam_instance_profile   = aws_iam_instance_profile.ipfs.name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.ipfs_root_volume_size
    delete_on_termination = true
    encrypted             = true

    tags = merge(
      var.common_tags,
      {
        Name = "${var.project_name}-ipfs-root"
      }
    )
  }

  ebs_block_device {
    device_name           = "/dev/sdf"
    volume_type           = "gp3"
    volume_size           = var.ipfs_data_volume_size
    delete_on_termination = true
    encrypted             = true

    tags = merge(
      var.common_tags,
      {
        Name = "${var.project_name}-ipfs-data"
      }
    )
  }

  user_data = base64encode(templatefile(
    "${path.module}/userdata/ipfs.sh",
    {
      ipfs_version  = var.ipfs_version
      ipfs_path     = var.ipfs_path
      ipfs_api_port = var.ipfs_api_port
    }
  ))

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-ipfs"
      Role = "ipfs"
    }
  )

  depends_on = [aws_route.private_nat_instance]
}

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

resource "aws_iam_role_policy" "ipfs_logs" {
  name = "${var.project_name}-ipfs-logs-policy"
  role = aws_iam_role.ipfs.id

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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${local.account_id}:log-group:${var.log_group_prefix}/ipfs/*"
      },
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

resource "aws_iam_instance_profile" "ipfs" {
  name = "${var.project_name}-ipfs-profile"
  role = aws_iam_role.ipfs.name
}

# Network Interface attachment for data volume
resource "aws_ec2_volume_attachment" "ipfs_data" {
  device_name = "/dev/sdf"
  instance_id = aws_instance.ipfs.id
  volume_id   = aws_ebs_volume.ipfs_data.id
}

# Create and manage data volume separately for better lifecycle management
resource "aws_ebs_volume" "ipfs_data" {
  availability_zone = var.availability_zone
  size              = var.ipfs_data_volume_size
  type              = "gp3"
  encrypted         = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-ipfs-data-volume"
    }
  )
}

# Outputs for IPFS
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
