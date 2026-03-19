# =============================================================
# Lambda Vectorizer Module
# Creates: ECR repo, Docker image build/push, Lambda function,
#          IAM role, security group, S3 trigger notification
# =============================================================

# ----------------------------------------------------------
# ECR repository for the vectorizer Docker image
# ----------------------------------------------------------
resource "aws_ecr_repository" "vectorizer" {
  name                 = "${var.project_name}-vectorizer"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "${var.project_name}-vectorizer" }
}

resource "aws_ecr_lifecycle_policy" "vectorizer" {
  repository = aws_ecr_repository.vectorizer.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

# ----------------------------------------------------------
# Build and push Docker image to ECR
# ----------------------------------------------------------
resource "null_resource" "vectorizer_image" {
  triggers = {
    dockerfile_hash = filemd5("${path.module}/docker/Dockerfile")
    handler_hash    = filemd5("${path.module}/docker/handler.py")
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws ecr get-login-password --region ${var.aws_region} | \
        docker login --username AWS --password-stdin ${aws_ecr_repository.vectorizer.repository_url}
      docker build --platform linux/amd64 \
        -t ${aws_ecr_repository.vectorizer.repository_url}:latest \
        ${path.module}/docker
      docker push ${aws_ecr_repository.vectorizer.repository_url}:latest
    EOT
  }

  depends_on = [aws_ecr_repository.vectorizer]
}

data "aws_ecr_image" "vectorizer" {
  repository_name = aws_ecr_repository.vectorizer.name
  image_tag       = "latest"
  depends_on      = [null_resource.vectorizer_image]
}

# ----------------------------------------------------------
# IAM Role for the Lambda function
# ----------------------------------------------------------
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vectorizer" {
  name               = "${var.project_name}-vectorizer-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "vectorizer_vpc" {
  role       = aws_iam_role.vectorizer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "vectorizer_inline" {
  name = "${var.project_name}-vectorizer-inline"
  role = aws_iam_role.vectorizer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Read"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:HeadObject"]
        Resource = ["${var.s3_bucket_arn}/*"]
      },
      {
        Sid    = "BedrockEmbeddings"
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = [
          "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.bedrock_embedding_model_id}"
        ]
      },
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:${var.elasticsearch_connection_secret}*"
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = [aws_ecr_repository.vectorizer.arn]
      }
    ]
  })
}

# ----------------------------------------------------------
# Security Group for the Lambda function
# ----------------------------------------------------------
resource "aws_security_group" "vectorizer_lambda" {
  name        = "${var.project_name}-vectorizer-lambda-sg"
  description = "Outbound-only SG for vectorizer Lambda"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound (Bedrock via NAT, Elastic via PrivateLink)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-vectorizer-lambda-sg" }
}

# ----------------------------------------------------------
# CloudWatch Log Group
# ----------------------------------------------------------
resource "aws_cloudwatch_log_group" "vectorizer" {
  name              = "/aws/lambda/${var.project_name}-vectorizer"
  retention_in_days = 14
}

# ----------------------------------------------------------
# Lambda Function
# ----------------------------------------------------------
resource "aws_lambda_function" "vectorizer" {
  function_name = "${var.project_name}-vectorizer"
  description   = "Generates and stores Elastic vector embeddings from S3 documents"
  role          = aws_iam_role.vectorizer.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.vectorizer.repository_url}:latest"
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.vectorizer_lambda.id]
  }

  environment {
    variables = {
      ELASTICSEARCH_ENDPOINT = var.elasticsearch_endpoint
      ELASTIC_SECRET_NAME    = var.elasticsearch_connection_secret
      ELASTIC_INDEX_NAME     = var.elastic_index_name
      BEDROCK_EMBEDDING_MODEL = var.bedrock_embedding_model_id
      AWS_REGION_NAME        = var.aws_region
      CHUNK_SIZE             = tostring(var.vectorizer_chunk_size)
      CHUNK_OVERLAP          = tostring(var.vectorizer_chunk_overlap)
    }
  }

  depends_on = [
    null_resource.vectorizer_image,
    aws_cloudwatch_log_group.vectorizer,
    aws_iam_role_policy_attachment.vectorizer_vpc
  ]

  tags = { Name = "${var.project_name}-vectorizer" }
}

# ----------------------------------------------------------
# Allow S3 to invoke the Lambda
# ----------------------------------------------------------
resource "aws_lambda_permission" "s3_invoke" {
  statement_id   = "AllowS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.vectorizer.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = var.s3_bucket_arn
  source_account = var.aws_account_id
}

# ----------------------------------------------------------
# S3 Event Notification → Lambda Vectorizer
# ----------------------------------------------------------
resource "aws_s3_bucket_notification" "vectorizer_trigger" {
  bucket = var.s3_bucket_id

  lambda_function {
    lambda_function_arn = aws_lambda_function.vectorizer.arn
    events              = ["s3:ObjectCreated:*"]
    # Trigger on all file types; the handler filters supported formats
  }

  depends_on = [aws_lambda_permission.s3_invoke]
}
