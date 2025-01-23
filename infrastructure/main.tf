# Create a target group for each RDS instance
resource "aws_lb_target_group" "rds_target_group" {
  for_each = { for inst in var.rds_instance_details : inst.name => inst }

  name        = "${substr(each.key, 0, 12)}-${each.value.listener_port}-tg"
  port        = data.aws_db_instance.rds_instance[each.key].port
  protocol    = "TCP"
  vpc_id      = data.aws_vpc.rds_vpc.id
  target_type = "ip"
}

# Attach a target to each target group
resource "aws_lb_target_group_attachment" "rds_target_group_attachment" {
  for_each = { for inst in var.rds_instance_details : inst.name => inst }

  target_group_arn = aws_lb_target_group.rds_target_group[each.key].arn
  target_id        = data.dns_a_record_set.rds_ip[each.key].addrs[0]

  lifecycle {
    ignore_changes = [target_id]
  }
  depends_on = [aws_lb_target_group.rds_target_group]
}

# Create a network Load Balancer
resource "aws_lb" "rds_lb" {
  name                             = var.nlb_name
  internal                         = true
  load_balancer_type               = "network"
  subnets                          = values(data.aws_subnet.rds_subnet)[*].id
  enable_cross_zone_load_balancing = var.cross_zone_load_balancing
  tags = {
    Name = var.nlb_name
  }
}

# Create listeners for each RDS instance, mapping each to its respective target group
resource "aws_lb_listener" "rds_listener" {
  for_each = { for inst in var.rds_instance_details : inst.name => inst }

  load_balancer_arn = aws_lb.rds_lb.arn
  port              = each.value.listener_port
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rds_target_group[each.key].arn
  }
}

# Create VPC endpoint service (PrivateLink) for the Load Balancer
resource "aws_vpc_endpoint_service" "rds_lb_endpoint_service" {
  acceptance_required        = var.acceptance_required
  network_load_balancer_arns = [aws_lb.rds_lb.arn]
  tags = {
    Name = "rds-nlb-endpoint-service"
  }
}

# Give Principals permission to create a VPC endpoint connection to the service
resource "aws_vpc_endpoint_service_allowed_principal" "rds_lb_endpoint_service_allowed_principal" {
  for_each                = toset(var.allowed_principal_arns)
  vpc_endpoint_service_id = aws_vpc_endpoint_service.rds_lb_endpoint_service.id
  principal_arn           = each.key
}


# Create an IAM policy for the Lambda function
resource "aws_iam_role" "lambda_execution_role" {
  name               = "lambda_execution_${substr(var.nlb_name, 0, 12)}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

# Create a Lambda function to check the RDS instance IP address
resource "aws_lambda_function" "check_rds_ip" {
  function_name = "${substr(var.nlb_name, 0, 12)}-check-rds-ip"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"

  filename = data.archive_file.lambda_zip.output_path

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      RDS_DETAILS = jsonencode({ for inst in var.rds_instance_details : inst.name => { port = inst.listener_port, target_group_arn = aws_lb_target_group.rds_target_group[inst.name].arn } })
    }
  }
}


# Create an IAM policy for the Lambda function
resource "aws_iam_role_policy" "lambda_execution_role_policy" {
  name   = "${substr(var.nlb_name, 0, 12)}-lambda-execution-role-policy"
  role   = aws_iam_role.lambda_execution_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "rds:DescribeDBInstances",
        "elasticloadbalancing:DescribeTargetHealth",
        "elasticloadbalancing:RegisterTargets",
        "elasticloadbalancing:DeregisterTargets"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_cloudwatch_event_rule" "rds_ip_check_rule" {
  name                = "${substr(var.nlb_name, 0, 12)}-rds-ip-check-rule"
  description         = "Fires every ${var.schedule_expression} to check the RDS instance IP address"
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "check_rds_ip_event_target" {
  rule      = aws_cloudwatch_event_rule.rds_ip_check_rule.name
  target_id = "${substr(var.nlb_name, 0, 12)}-check-rds-ip"
  arn       = aws_lambda_function.check_rds_ip.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_check_rds_ip" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.check_rds_ip.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.rds_ip_check_rule.arn
}

#Rds Proxy
resource "aws_rds_proxy" "rds_proxy" {
  for_each           = { for inst in var.rds_instance_details : inst.name => inst }
  name               = "${each.key}-proxy"
  role_arn           = aws_iam_role.rds_proxy_role.arn
  vpc_security_group_ids = var.security_group_ids
  vpc_subnet_ids     = values(data.aws_subnet.rds_subnet)[*].id
  engine_family      = "POSTGRESQL"
  idle_client_timeout = 1800
  require_tls        = true

  auth {
    auth_scheme = "SECRETS"
    iam_auth    = "DISABLED"
    secret_arn  = aws_secretsmanager_secret.rds_proxy_secret[each.key].arn
  }
}

#IAM Role for RDS Instance
resource "aws_iam_role" "rds_proxy_role" {
  name               = "rds_proxy_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

resource "aws_iam_policy" "rds_proxy_policy" {
  name        = "rds_proxy_policy"
  description = "Policy for RDS Proxy"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "secretsmanager:GetSecretValue",
        "rds:DescribeDBInstances"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "rds_proxy_policy_attach" {
  role       = aws_iam_role.rds_proxy_role.name
  policy_arn = aws_iam_policy.rds_proxy_policy.arn
}

# sg-087da1a472ae9b952