module "rdsprivatelink" {
  source = "./modules"

  rds_instance_details = var.rds_instance_details
  rds_vpc_id = var.rds_vpc_id
  nlb_name = var.nlb_name
  acceptance_required = var.acceptance_required
  schedule_expression = var.schedule_expression
  cross_zone_load_balancing = var.cross_zone_load_balancing
  allowed_principal_arns = var.allowed_principal_arns
}