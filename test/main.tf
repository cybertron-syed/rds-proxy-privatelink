# Define provider
provider "aws" {
  region = "us-east-1" 
}

# Create a VPC -
resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
}

# Create subnets in different Availability Zones -
resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}
# -
resource "aws_subnet" "private_subnet_b" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
}

# Create a security group for RDS -
resource "aws_security_group" "rds_security_group" {
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port   = 5432
    to_port     = 5432
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

# Create an RDS PostgreSQL instance -
resource "aws_db_instance" "hopper_postgres" {
  allocated_storage      = 20
  engine                 = "postgres"
  engine_version         = "16.4"
  instance_class         = "db.t3.micro"
  db_name                = "HopperDB"
  identifier             = "hopper-postgres-db"
  username               = "db_admin"
  password               = "securepostgres"
  vpc_security_group_ids = [aws_security_group.rds_security_group.id]
  db_subnet_group_name   = aws_db_subnet_group.hopper_subnet_group.name

  skip_final_snapshot = true
}

# Create a DB subnet group -
resource "aws_db_subnet_group" "hopper_subnet_group" {
  name       = "hopper-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
}

# Create an RDS Proxy for PostgreSQL -
resource "aws_db_proxy" "hopper_rds_proxy" {
  name                   = "hopper-postgres-proxy"
  engine_family          = "POSTGRESQL"
  role_arn               = aws_iam_role.rds_proxy_role.arn
  vpc_security_group_ids = [aws_security_group.rds_security_group.id]
  vpc_subnet_ids         = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
  require_tls            = true

  auth {
    auth_scheme = "SECRETS"
    secret_arn  = aws_secretsmanager_secret.postgres_secret.arn
  }
}

# Create an IAM role for RDS Proxy -
resource "aws_iam_role" "rds_proxy_role" {
  name = "hopper-rds-proxy-role"

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

# Create a Secrets Manager secret to store database credentials -
resource "aws_secretsmanager_secret" "postgres_secret" {
  name = "hopper-db-creds-v2"

  # secret_string = jsonencode({
  #   username = "admin"
  #   password = "securepostgres"
  # })
}

# Attach the necessary policy to the IAM role -
resource "aws_iam_role_policy_attachment" "rds_proxy_policy_attachment" {
  role       = aws_iam_role.rds_proxy_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
}

# Create a Network Load Balancer - 
resource "aws_lb" "rds_nlb" {
  name               = "hopper-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
}

# Create a target group for the NLB - instance -
resource "aws_lb_target_group" "rds_proxy_tg" {
  name        = "hopper-proxy-target-group"
  port        = 5432
  protocol    = "TCP"
  vpc_id      = aws_vpc.main_vpc.id
  target_type = "ip"
}

# External data source to resolve the DNS name of the RDS Proxy to an IP address -
data "external" "rds_proxy_ip" {
  program = [
    "bash", "-c", <<EOT
      IP=$(dig +short ${aws_db_proxy.hopper_rds_proxy.endpoint} | grep -E '^[0-9]+(\.[0-9]+){3}$' | head -n 1)
      if [ -z "$IP" ]; then
        echo "{\"ip\": \"\"}"
      else
        echo "{\"ip\": \"$IP\"}"
      fi
    EOT
  ]
}

# Attach the IP address to the NLB target group -
resource "aws_lb_target_group_attachment" "rds_proxy_attachment" {
  target_group_arn = aws_lb_target_group.rds_proxy_tg.arn
  target_id        = data.external.rds_proxy_ip.result["ip"]  
  port             = 5432
}

# Create a listener for the NLB -
resource "aws_lb_listener" "rds_proxy_listener" {
  load_balancer_arn = aws_lb.rds_nlb.arn
  port              = 5432
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rds_proxy_tg.arn
  }
}

# Create a VPC Endpoint Service for the NLB -
resource "aws_vpc_endpoint_service" "rds_proxy_endpoint_service" {
  acceptance_required    = false
  network_load_balancer_arns = [aws_lb.rds_nlb.arn]
}

# Output the service name for cross-account access
output "vpc_endpoint_service_name" {
  value = aws_vpc_endpoint_service.rds_proxy_endpoint_service.service_name
}

# Fetch DNS name of RDS Proxy
output "rds_proxy_dns_name" {
  value = aws_db_proxy.hopper_rds_proxy.endpoint
}
