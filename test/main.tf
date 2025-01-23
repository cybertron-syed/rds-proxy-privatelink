# Define provider
provider "aws" {
  region = "us-east-1" # Specify your AWS region
}

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Create subnets in different Availability Zones
resource "aws_subnet" "subnet_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "subnet_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
}

# Create a security group for RDS
resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create an RDS instance
resource "aws_db_instance" "hopper" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  db_name              = "Test"
  identifier           = "hopper-db"
  username             = "admin"
  password             = "password"
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.main.name

  skip_final_snapshot = true
}

# Create a DB subnet group
resource "aws_db_subnet_group" "main" {
  name       = "main"
  subnet_ids = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id]
}

# Create an RDS Proxy
resource "aws_db_proxy" "rds_proxy" {
  name                   = "hopper-proxy"
  engine_family          = "MYSQL"
  role_arn               = aws_iam_role.rds_proxy_role.arn
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  vpc_subnet_ids         = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id]
  require_tls            = true

  auth {
    auth_scheme = "SECRETS"
    secret_arn  = aws_secretsmanager_secret.example.arn
  }
}


# Create an IAM role for RDS Proxy
resource "aws_iam_role" "rds_proxy_role" {
  name = "rds-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
      },
    ]
  })
}



# Create a Secrets Manager secret to store database credentials
resource "aws_secretsmanager_secret" "example" {
  name = "db-credentials-env3"

}

resource "aws_iam_role_policy_attachment" "rds_proxy_policy" {
  role       = aws_iam_role.rds_proxy_role.name
  policy_arn = "arn:aws:iam::aws:policy/CustomRDSProxyServiceRolePolicy"
}


# Create a Network Load Balancer
resource "aws_lb" "nlb" {
  name               = "example-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id]
}

# Create a target group for the NLB - ip
resource "aws_lb_target_group" "rds_proxy_tg" {
  name        = "rds-proxy-tg"
  port        = 3306
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
}


# Register the RDS Proxy with the target group
resource "aws_lb_target_group_attachment" "rds_proxy_attachment" {
  target_group_arn = aws_lb_target_group.rds_proxy_tg.arn
  target_id        = aws_db_proxy.example.endpoint
  port             = 3306
}

# Create a listener for the NLB
resource "aws_lb_listener" "rds_proxy_listener" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 3306
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rds_proxy_tg.arn
  }
}

# Create a VPC Endpoint Service for the NLB
resource "aws_vpc_endpoint_service" "rds_proxy_service" {
  acceptance_required = false
  network_load_balancer_arns = [aws_lb.nlb.arn]
}

# Output the service name for cross-account access
output "vpc_endpoint_service_name" {
  value = aws_vpc_endpoint_service.rds_proxy_service.service_name
}