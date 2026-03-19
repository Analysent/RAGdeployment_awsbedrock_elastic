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

  # ── Remote state backend (recommended for production) ──────────────────
  # Uncomment and fill in to store state in S3 instead of locally.
  # State files can contain sensitive resource attributes — never commit them.
  #
  # backend "s3" {
  #   bucket         = "<YOUR_TERRAFORM_STATE_BUCKET>"
  #   key            = "rag-elastic/terraform.tfstate"
  #   region         = "<YOUR_AWS_REGION>"
  #   dynamodb_table = "<YOUR_LOCK_TABLE>"
  #   encrypt        = true
  # }
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
