variable "project_name" {
  type = string
}

variable "deployment_id" {
  description = "Elastic deployment ID used as bucket name suffix"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "private_route_table_ids" {
  description = "Route table IDs for private subnets (used by S3 gateway endpoint)"
  type        = list(string)
}

variable "aws_region" {
  type = string
}

variable "aws_account_id" {
  type = string
}
