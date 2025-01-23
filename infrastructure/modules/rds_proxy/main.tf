#Rds Proxy
resource "aws_rds_proxy" "rds_proxy" {
  for_each           = { for inst in var.rds_instance_details : inst.name => inst }
  name               = "${each.key}-proxy"
  role_arn           = aws_iam_role.rds_proxy_role.arn
  vpc_security_group_ids = var.security_group_ids
  vpc_subnet_ids     = values(data.aws_subnet.rds_subnet)[*].id
  engine_family      = data.aws_db_instance.rds_instance[each.key].engine
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