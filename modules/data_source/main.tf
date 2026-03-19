# =============================================================
# Data Source Module
# Creates: S3 bucket (private), S3 VPC gateway endpoint,
#          bucket policy restricting access to VPC endpoint
# =============================================================

# ----------------------------------------------------------
# S3 bucket — named with deployment ID as unique suffix
# ----------------------------------------------------------
resource "aws_s3_bucket" "data_source" {
  bucket        = "data-source-${var.deployment_id}"
  force_destroy = false

  tags = { Name = "data-source-${var.deployment_id}" }
}

resource "aws_s3_bucket_versioning" "data_source" {
  bucket = aws_s3_bucket.data_source.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_source" {
  bucket = aws_s3_bucket.data_source.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "data_source" {
  bucket                  = aws_s3_bucket.data_source.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ----------------------------------------------------------
# S3 VPC Gateway Endpoint — free, no data charges, low latency
# ----------------------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids

  tags = { Name = "${var.project_name}-s3-endpoint" }
}

# ----------------------------------------------------------
# Bucket policy — allow access only via the VPC endpoint
# (Lambda inside VPC will use the gateway endpoint automatically)
# ----------------------------------------------------------
resource "aws_s3_bucket_policy" "data_source" {
  bucket = aws_s3_bucket.data_source.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonVpcEndpointAccess"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.data_source.arn,
          "${aws_s3_bucket.data_source.arn}/*"
        ]
        Condition = {
          StringNotEquals = {
            "aws:sourceVpce" = aws_vpc_endpoint.s3.id
          }
        }
      },
      {
        Sid       = "AllowLambdaViaVpcEndpoint"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.aws_account_id}:root" }
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.data_source.arn,
          "${aws_s3_bucket.data_source.arn}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:sourceVpce" = aws_vpc_endpoint.s3.id
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.data_source]
}

# ----------------------------------------------------------
# S3 bucket notification (wired to Lambda in lambda_vectorizer module)
# The actual aws_s3_bucket_notification is created in lambda_vectorizer
# to avoid circular dependency; only the bucket is created here.
# ----------------------------------------------------------
