variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name prefix for resource naming"
  type        = string
  default     = "rag-elastic"
}

# ----------------------------------------------------------
# Elastic Cloud
# ----------------------------------------------------------
variable "deployment_id" {
  description = "Unique ID of the Elastic Cloud deployment (used for naming and PrivateLink)"
  type        = string
}

variable "elasticsearch_endpoint" {
  description = "Elasticsearch HTTPS endpoint (e.g. https://<deployment-id>.us-east-1.aws.elastic-cloud.com:9243)"
  type        = string
}

variable "elasticsearch_connection_secret" {
  description = "Name of the AWS Secrets Manager secret containing Elastic credentials (keys: username, password)"
  type        = string
}

variable "elastic_private_link_service_name" {
  description = "AWS PrivateLink service name for the Elastic Cloud region (from Elastic Cloud console)"
  type        = string
  # Example: com.amazonaws.vpce.us-east-1.vpce-svc-0e42e1e06ed010238
}

variable "elastic_private_link_zone_name" {
  description = "Private hosted zone DNS name for Elastic PrivateLink (region-specific)"
  type        = string
  default     = "us-east-1.aws.elastic-cloud.com"
  # See: https://www.elastic.co/guide/en/cloud/current/ec-traffic-filtering-vpc.html
}

variable "elastic_index_name" {
  description = "Elasticsearch index name for storing document vectors"
  type        = string
  default     = "documents"
}

# ----------------------------------------------------------
# Networking
# ----------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones to use (must be >= 2)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

# ----------------------------------------------------------
# Amazon Bedrock
# ----------------------------------------------------------
variable "bedrock_embedding_model_id" {
  description = "Amazon Bedrock model ID for text embeddings"
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "bedrock_llm_model_id" {
  description = "Amazon Bedrock model ID for text generation"
  type        = string
  default     = "amazon.titan-text-express-v1"
}

# ----------------------------------------------------------
# Lambda
# ----------------------------------------------------------
variable "lambda_memory_size" {
  description = "Memory (MB) allocated to Lambda functions"
  type        = number
  default     = 1024
}

variable "lambda_timeout" {
  description = "Timeout (seconds) for Lambda functions"
  type        = number
  default     = 300
}

variable "vectorizer_chunk_size" {
  description = "Number of characters per document chunk for vectorization"
  type        = number
  default     = 1000
}

variable "vectorizer_chunk_overlap" {
  description = "Character overlap between consecutive document chunks"
  type        = number
  default     = 200
}
