# Provider configuration
provider "aws" {
  region = "us-east-1"
}

# VPC creation
resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
}

# Subnets in different availability zones
resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "private_subnet_b" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
}

resource "aws_subnet" "public_subnet_a" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "public_subnet_b" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
}

# Security Group for RDS Proxy and DB Cluster
resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]  # Allow access from private subnets to DB
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create RDS Proxy
resource "aws_db_proxy" "hopper_rds_proxy" {
  name                   = "hopper-postgres-proxy"
  engine_family          = "POSTGRESQL"
  role_arn               = aws_iam_role.rds_proxy_role.arn
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  vpc_subnet_ids         = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
  require_tls            = true
  auth {
    auth_scheme = "SECRETS"
    secret_arn  = aws_secretsmanager_secret.postgres_secret.arn
  }
}

# IAM role for RDS Proxy
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

# Create Secrets Manager secret to store DB credentials

# Create the NLB (Network Load Balancer)
resource "aws_lb" "rds_nlb" {
  name               = "hopper-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
}

# Create a target group for NLB
resource "aws_lb_target_group" "rds_proxy_tg" {
  name        = "hopper-proxy-target-group"
  port        = 5432
  protocol    = "TCP"
  vpc_id      = aws_vpc.main_vpc.id
  target_type = "ip"
}

# Create an NLB listener
resource "aws_lb_listener" "rds_proxy_listener" {
  load_balancer_arn = aws_lb.rds_nlb.arn
  port              = 5432
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rds_proxy_tg.arn
  }
}

# VPC Endpoint for Privatelink
resource "aws_vpc_endpoint_service" "rds_proxy_endpoint_service" {
  acceptance_required = false
  network_load_balancer_arns = [aws_lb.rds_nlb.arn]
}

# Output the VPC endpoint service name
output "vpc_endpoint_service_name" {
  value = aws_vpc_endpoint_service.rds_proxy_endpoint_service.service_name
}

# Lambda function to update target group with RDS Proxy DNS name
resource "aws_lambda_function" "update_target_group" {
  filename         = "main.zip"  # The zipped package that includes your Lambda code
  function_name    = "main"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "python3.8"

  environment {
    variables = {
      TARGET_GROUP_ARN = aws_lb_target_group.rds_proxy_tg.arn
      RDS_PROXY_ENDPOINT = aws_db_proxy.hopper_rds_proxy.endpoint
    }
  }
}

# IAM role for Lambda execution
resource "aws_iam_role" "lambda_exec_role" {
  name               = "lambda_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

# Attach Lambda permissions to interact with NLB Target Groups
resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets"
        ],
        Effect   = "Allow",
        Resource = aws_lb_target_group.rds_proxy_tg.arn
      },
    ]
  })
}

# Lambda function to update target group with RDS Proxy DNS name
resource "aws_lambda_permission" "allow_lambda_invocation" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  principal     = "events.amazonaws.com"
  function_name = aws_lambda_function.update_target_group.function_name
}

# Create a CloudWatch Event rule to trigger Lambda periodically (for testing purposes)
resource "aws_cloudwatch_event_rule" "schedule" {
  name        = "lambda_trigger_schedule"
  description = "Trigger Lambda every 5 minutes to update NLB target"
  schedule_expression = "rate(5 minutes)"
}

# Event rule targets Lambda
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "lambda_trigger"
  arn       = aws_lambda_function.update_target_group.arn
}

# Create the NLB Target Group attachment
resource "aws_lb_target_group_attachment" "rds_proxy_attachment" {
  target_group_arn = aws_lb_target_group.rds_proxy_tg.arn
  target_id        = aws_db_proxy.hopper_rds_proxy.endpoint  # This is the RDS Proxy DNS name
  port             = 5432
}

