terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    elasticstack = {
      source  = "elastic/elasticstack"
      version = "~> 0.11"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "rag-elastic-bedrock"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Elastic Cloud provider uses EC_API_KEY env variable automatically
provider "elasticstack" {
  elasticsearch {}
}
