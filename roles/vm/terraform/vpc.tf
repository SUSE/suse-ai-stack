resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "${var.aws["resource_prefix"]}-dev-ai-vpc"
    Owner = "${var.aws["resource_owner"]}"
    Project = "ai"
  }
}

resource "aws_internet_gateway" "igw" {
  depends_on = [aws_vpc.main]
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.aws["resource_prefix"]}-dev-ai-igw"
    Owner = "${var.aws["resource_owner"]}"
    Project = "ai"
  }
}

resource "aws_subnet" "subnet1" {
  depends_on = [aws_vpc.main]
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.0.0/19"
  availability_zone = var.aws["az1"]

  map_public_ip_on_launch = true

  tags = {
    Name = "${var.aws["resource_prefix"]}-dev-ai-subnet1"
    Owner = "${var.aws["resource_owner"]}"
    Project = "ai"
  }
}

resource "aws_subnet" "subnet2" {
  depends_on = [aws_vpc.main]
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.32.0/19"
  availability_zone = var.aws["az2"]

  map_public_ip_on_launch = true

  tags = {
    Name = "${var.aws["resource_prefix"]}-dev-ai-subnet2"
    Owner = "${var.aws["resource_owner"]}"
    Project = "ai"
  }
}

resource "aws_route_table" "rt" {
  depends_on = [aws_vpc.main]
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.aws["resource_prefix"]}-dev-ai-rt"
    Owner = "${var.aws["resource_owner"]}"
    Project = "ai"
  }
}

resource "aws_route" "route-igw" {
  depends_on = [aws_route_table.rt, aws_internet_gateway.igw]
  route_table_id            = aws_route_table.rt.id
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id                = aws_internet_gateway.igw.id
}


resource "aws_route_table_association" "subnet1" {
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_route_table_association" "subnet2" {
  subnet_id      = aws_subnet.subnet2.id
  route_table_id = aws_route_table.rt.id
}

#data "http" "myip" {
  ##url = "http://ipv4.icanhazip.com"
  #url = "http://ipinfo.io/ip"
#}


resource "aws_security_group" "sg" {
  depends_on = [aws_vpc.main]
  name        = "${var.aws["resource_prefix"]}-dev-ai-sg-restrictedports"
  description = "sg ai"
  vpc_id      = aws_vpc.main.id

  #https://docs.rke2.io/install/requirements#inbound-network-rules
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    #cidr_blocks =  [aws_vpc.main.cidr_block, "${chomp(data.http.myip.response_body)}/32"] #restricted SSH
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 2376
    to_port     = 2376
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 4789
    to_port     = 4789
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 5473
    to_port     = 5473
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8472
    to_port     = 8472
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 9099
    to_port     = 9099
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 51820
    to_port     = 51821
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 9345
    to_port     = 9345
    protocol    = "tcp"
   cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 9796
    to_port     = 9796
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 10256
    to_port     = 10256
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 10443
    to_port     = 10443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 11443
    to_port     = 11443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.aws["resource_prefix"]}-dev-ai-rancher-rt"
    Owner = "${var.aws["resource_owner"]}"
    Project = "ai"
  }
}
