variable "rds_instance_details" {
  type = map(object({
    listener_port = number
  }))
}

variable "nlb_name" {
  type = string
}

variable "acceptance_required" {
  type = bool
}

variable "schedule_expression" {
  type = string
}

variable "cross_zone_load_balancing" {
  type = bool
}

variable "allowed_principal_arns" {
  type = list(string)
}

variable "rds_vpc_id" {
  type = string
}
