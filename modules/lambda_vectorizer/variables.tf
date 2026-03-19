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

variable "s3_bucket_id" {
  description = "S3 data-source bucket name"
  type        = string
}

variable "s3_bucket_arn" {
  description = "S3 data-source bucket ARN"
  type        = string
}

variable "elasticsearch_endpoint" {
  description = "Elasticsearch HTTPS endpoint"
  type        = string
}

variable "elasticsearch_connection_secret" {
  description = "Secrets Manager secret name for Elastic credentials"
  type        = string
}

variable "elastic_index_name" {
  type = string
}

variable "bedrock_embedding_model_id" {
  type = string
}

variable "lambda_memory_size" {
  type = number
}

variable "lambda_timeout" {
  type = number
}

variable "vectorizer_chunk_size" {
  type = number
}

variable "vectorizer_chunk_overlap" {
  type = number
}
