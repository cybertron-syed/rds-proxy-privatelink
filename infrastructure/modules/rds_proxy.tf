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
