variable "project_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "aws_account_id" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "elasticsearch_endpoint" {
  type = string
}

variable "elasticsearch_connection_secret" {
  type = string
}

variable "elastic_index_name" {
  type = string
}

variable "bedrock_embedding_model_id" {
  type = string
}

variable "bedrock_llm_model_id" {
  type = string
}

variable "lambda_memory_size" {
  type = number
}

variable "lambda_timeout" {
  type = number
}

variable "vectorizer_security_group_id" {
  description = "Reuse vectorizer SG so the agent can also reach Elastic endpoint"
  type        = string
}
