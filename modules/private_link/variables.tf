variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "elastic_private_link_service_name" {
  description = "AWS PrivateLink endpoint service name from Elastic Cloud Console"
  type        = string
}

variable "elastic_private_link_zone_name" {
  description = "DNS zone name for Elastic PrivateLink (e.g. us-east-1.aws.elastic-cloud.com)"
  type        = string
}

variable "deployment_id" {
  description = "Elastic deployment ID"
  type        = string
}

variable "lambda_security_group_id" {
  description = "Security group ID of the Lambda functions that need access to Elastic"
  type        = string
}
