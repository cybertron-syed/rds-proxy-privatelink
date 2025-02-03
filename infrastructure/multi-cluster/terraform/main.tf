variable "create" {
  description = "Whether to create the RDS Proxy and associated resources"
  type        = bool
  default     = true
}

variable "db_cluster_identifier" {
  description = "The identifier of the existing DB cluster"
  type        = string
  default     = "my-existing-cluster"
}

variable "auth" {
  default = [
    {
      auth_scheme  = "SECRETS"
      secret_arn   = "arn:aws:secretsmanager:region:account-id:secret:your-secret-name"
      username     = "your-db-username"
    }
  ]
}

resource "aws_db_proxy" "this" {
  count = var.create ? 1 : 0

  dynamic "auth" {
    for_each = var.auth

    content {
      auth_scheme               = try(auth.value.auth_scheme, "SECRETS")
      client_password_auth_type = try(auth.value.client_password_auth_type, null)
      description               = try(auth.value.description, null)
      iam_auth                  = try(auth.value.iam_auth, null)
      secret_arn                = try(auth.value.secret_arn, null)
      username                  = try(auth.value.username, null)
    }
  }

  debug_logging          = var.debug_logging
  engine_family          = var.engine_family
  idle_client_timeout    = var.idle_client_timeout
  name                   = var.name
  require_tls            = var.require_tls
  role_arn               = local.role_arn
  vpc_security_group_ids = var.vpc_security_group_ids
  vpc_subnet_ids         = var.vpc_subnet_ids

  tags = merge(var.tags, var.proxy_tags)

  depends_on = [aws_cloudwatch_log_group.this]
}

resource "aws_db_proxy_target" "db_cluster" {
  count = var.create && var.target_db_cluster && var.db_cluster_identifier != "" ? 1 : 0

  db_proxy_name         = aws_db_proxy.this[0].name
  target_group_name     = aws_db_proxy_default_target_group.this[0].name
  db_cluster_identifier = var.db_cluster_identifier
}

resource "aws_db_proxy_endpoint" "this" {
  for_each = { for k, v in var.endpoints : k => v if var.create }

  db_proxy_name          = aws_db_proxy.this[0].name
  db_proxy_endpoint_name = each.value.name
  vpc_subnet_ids         = each.value.vpc_subnet_ids
  vpc_security_group_ids = lookup(each.value, "vpc_security_group_ids", null)
  target_role            = lookup(each.value, "target_role", null)

  tags = lookup(each.value, "tags", var.tags)
}
