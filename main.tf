resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "challenge-terraform"
  }
}

resource "aws_subnet" "subnet_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-northeast-1a"

  tags = {
    Name = "challenge-terraform"
  }
}

resource "aws_subnet" "subnet_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-northeast-1c"

  tags = {
    Name = "challenge-terraform"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "challenge-terraform"
  }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "challenge-terraform"
  }
}

resource "aws_route" "main" {
  destination_cidr_block = "0.0.0.0/0"
  route_table_id         = aws_route_table.main.id
  gateway_id             = aws_internet_gateway.main.id # Internet Gateway への経路情報を追加
}

resource "aws_route_table_association" "association_a" {
  subnet_id      = aws_subnet.subnet_a.id # Public Subnetと紐付け
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "association_b" {
  subnet_id      = aws_subnet.subnet_b.id # Public Subnetと紐付け
  route_table_id = aws_route_table.main.id
}