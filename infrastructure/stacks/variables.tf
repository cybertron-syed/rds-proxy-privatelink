variable "rds_instance_details" {
  default = {
    "rds-instance-1" = {
      listener_port = 5432
    },
    "rds-instance-2" = {
      listener_port = 3306
    }
  }
}

variable "nlb_name" {
  default = "test-rds-nlb"
}

variable "cross_zone_load_balancing" {
  default = true
}

variable "acceptance_required" {
  default = false
}

variable "allowed_principal_arns" {
  default = [
    "arn:aws:iam::123456789012:role/AllowedRole"
  ]
}

variable "schedule_expression" {
  default = "rate(5 minutes)"
}

variable "rds_vpc_id" {
  default = "vpc-06581feaf24fcca1b"
}