# VPC
resource "aws_vpc" "sentinel" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name    = "sentinel-vpc"
    Project = "Sentinel Network"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "sentinel" {
  vpc_id = aws_vpc.sentinel.id

  tags = {
    Name    = "sentinel-igw"
    Project = "Sentinel Network"
  }
}

# Public Subnet (for bastion, NAT instance, NGINX)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.sentinel.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name    = "sentinel-public-subnet"
    Type    = "public"
    Project = "Sentinel Network"
  }
}

# Private Subnet (for services, IPFS, databases)
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.sentinel.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name    = "sentinel-private-subnet"
    Type    = "private"
    Project = "Sentinel Network"
  }
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.sentinel.id

  tags = {
    Name    = "sentinel-public-rt"
    Project = "Sentinel Network"
  }
}

# Public Route to Internet Gateway
resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.sentinel.id
}

# Associate Public Subnet with Public Route Table
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.sentinel.id

  tags = {
    Name    = "sentinel-private-rt"
    Project = "Sentinel Network"
  }
}

# Associate Private Subnet with Private Route Table
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

