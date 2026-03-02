resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.bastion_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name

  associate_public_ip_address = true

  user_data = base64encode(file("${path.module}/userdata/bastion.sh"))

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-bastion"
      Role = "bastion"
    }
  )

  depends_on = [aws_internet_gateway.sentinel]
}
