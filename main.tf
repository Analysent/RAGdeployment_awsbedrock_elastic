# =============================================================
# RAG with Elastic Cloud + Amazon Bedrock + AWS Lambda
# Root module — orchestrates all child modules
# =============================================================

# ----------------------------------------------------------
# Data sources
# ----------------------------------------------------------
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ----------------------------------------------------------
# VPC
# ----------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  aws_region           = var.aws_region
}

# ----------------------------------------------------------
# Data Source  (S3 bucket + S3 VPC endpoint)
# ----------------------------------------------------------
module "data_source" {
  source = "./modules/data_source"

  project_name   = var.project_name
  deployment_id  = var.deployment_id
  vpc_id         = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  private_route_table_ids = module.vpc.private_route_table_ids
  aws_region     = var.aws_region
  aws_account_id = data.aws_caller_identity.current.account_id
}

# ----------------------------------------------------------
# Private Link  (Elastic Cloud <-> VPC)
# ----------------------------------------------------------
module "private_link" {
  source = "./modules/private_link"

  project_name                       = var.project_name
  vpc_id                             = module.vpc.vpc_id
  private_subnet_ids                 = module.vpc.private_subnet_ids
  elastic_private_link_service_name  = var.elastic_private_link_service_name
  elastic_private_link_zone_name     = var.elastic_private_link_zone_name
  deployment_id                      = var.deployment_id
  lambda_security_group_id           = module.lambda_vectorizer.lambda_security_group_id
}

# ----------------------------------------------------------
# Lambda Vectorizer  (S3 → Bedrock embeddings → Elastic)
# ----------------------------------------------------------
module "lambda_vectorizer" {
  source = "./modules/lambda_vectorizer"

  project_name                    = var.project_name
  aws_region                      = var.aws_region
  aws_account_id                  = data.aws_caller_identity.current.account_id
  vpc_id                          = module.vpc.vpc_id
  private_subnet_ids              = module.vpc.private_subnet_ids
  s3_bucket_id                    = module.data_source.bucket_id
  s3_bucket_arn                   = module.data_source.bucket_arn
  elasticsearch_endpoint          = var.elasticsearch_endpoint
  elasticsearch_connection_secret = var.elasticsearch_connection_secret
  elastic_index_name              = var.elastic_index_name
  bedrock_embedding_model_id      = var.bedrock_embedding_model_id
  lambda_memory_size              = var.lambda_memory_size
  lambda_timeout                  = var.lambda_timeout
  vectorizer_chunk_size           = var.vectorizer_chunk_size
  vectorizer_chunk_overlap        = var.vectorizer_chunk_overlap
}

# ----------------------------------------------------------
# Lambda Agent  (question → Elastic similarity search → Bedrock → answer)
# ----------------------------------------------------------
module "lambda_agent" {
  source = "./modules/lambda_agent"

  project_name                    = var.project_name
  aws_region                      = var.aws_region
  aws_account_id                  = data.aws_caller_identity.current.account_id
  vpc_id                          = module.vpc.vpc_id
  private_subnet_ids              = module.vpc.private_subnet_ids
  elasticsearch_endpoint          = var.elasticsearch_endpoint
  elasticsearch_connection_secret = var.elasticsearch_connection_secret
  elastic_index_name              = var.elastic_index_name
  bedrock_embedding_model_id      = var.bedrock_embedding_model_id
  bedrock_llm_model_id            = var.bedrock_llm_model_id
  lambda_memory_size              = var.lambda_memory_size
  lambda_timeout                  = var.lambda_timeout
  vectorizer_security_group_id    = module.lambda_vectorizer.lambda_security_group_id
}

# ----------------------------------------------------------
# API Gateway  (HTTP API → Lambda Agent)
# ----------------------------------------------------------
module "api_gateway" {
  source = "./modules/api_gateway"

  project_name          = var.project_name
  lambda_agent_arn      = module.lambda_agent.lambda_arn
  lambda_agent_invoke_arn = module.lambda_agent.lambda_invoke_arn
  aws_region            = var.aws_region
  aws_account_id        = data.aws_caller_identity.current.account_id
}
