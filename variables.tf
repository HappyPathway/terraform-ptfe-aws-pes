variable "namespace" {}
variable "aws_instance_type" {}
variable "ssh_key_name" {}
variable "owner" {}
variable "ttl" {}

variable "subnet_ids" {
  type = "list"
}

variable "vpc_security_group_ids" {}
variable "route53_zone" {}
variable "private_route53_zone" {}
variable "database_pwd" {}
variable "db_subnet_group_name" {}
