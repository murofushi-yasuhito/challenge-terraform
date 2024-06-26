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

data "aws_ami" "main" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.main.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.subnet_a.id
  vpc_security_group_ids = [aws_security_group.allow_http.id]

  iam_instance_profile = aws_iam_instance_profile.assume_role_profile.name

  tags = {
    Name = "challenge-terraform"
  }

  user_data = <<-EOF
  #!/bin/bash
  sudo apt-get update -y
  sudo apt-get install nginx -y
  sudo systemctl start nginx
  sudo systemctl enable nginx
  EOF
}

resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow inbound traffic on port 80"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "assume_role" {
  name = "assume_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Effect = "Allow",
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy_attachment" {
  role       = aws_iam_role.assume_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "assume_role_profile" {
  name = "assume_role_profile"
  role = aws_iam_role.assume_role.name
}

resource "aws_lb" "main" {
  name               = "main-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_http.id]

  subnets = [
    aws_subnet.subnet_a.id,
    aws_subnet.subnet_b.id
  ]
  #   enable_deletion_protection = false // 削除保護を無効にする

  tags = {
    Environment = "challenge-terraform"
  }
}

resource "aws_lb_target_group" "main" {
  name             = "main-target-group"
  target_type      = "instance"
  protocol_version = "HTTP1"
  port             = 80
  protocol         = "HTTP"

  vpc_id = aws_vpc.main.id

  tags = {
    Name = "challenge-terraform"
  }

  health_check {
    interval            = 10
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200,301"
  }
}

resource "aws_lb_target_group_attachment" "main" {
  target_group_arn = aws_lb_target_group.main.arn
  target_id        = aws_instance.web.id
}

resource "aws_lb_listener" "test_listener" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

data "aws_route53_zone" "main" {
  name = "morishita-aws.net"
}

resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = data.aws_route53_zone.main.name
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  type            = each.value.type
  ttl             = "300"

  zone_id = data.aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate" "cert" {
  domain_name               = data.aws_route53_zone.main.name
  subject_alternative_names = ["*.${data.aws_route53_zone.main.name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "cert_valid" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}


resource "aws_lb_target_group" "hands_on_target_group443" {
  name             = "test-target-group443"
  target_type      = "instance"
  protocol_version = "HTTP1"
  port             = 80
  protocol         = "HTTP"

  vpc_id = aws_vpc.main.id

  tags = {
    Name = "challenge-terraform"
  }

  health_check {
    interval            = 15
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200,301"
  }
}

resource "aws_lb_listener" "hands-on-listener443" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.hands_on_target_group443.arn
  }
}

resource "aws_lb_target_group_attachment" "hands_on_target_ec2_443" {
  target_group_arn = aws_lb_target_group.hands_on_target_group443.arn
  target_id        = aws_instance.web.id
}

