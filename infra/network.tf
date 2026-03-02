resource "aws_vpc" "sentinel" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-vpc"
    }
  )
}

resource "aws_internet_gateway" "sentinel" {
  vpc_id = aws_vpc.sentinel.id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-igw"
    }
  )
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.sentinel.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-public-subnet"
      Type = "public"
    }
  )
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.sentinel.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-private-subnet"
      Type = "private"
    }
  )
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.sentinel.id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-public-rt"
    }
  )
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.sentinel.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.sentinel.id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-private-rt"
    }
  )
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

