# =============================================================
# Lambda Agent Module
# Creates: ECR repo, Docker image, Lambda function (RAG agent),
#          IAM role, security group
# =============================================================

# ----------------------------------------------------------
# ECR repository
# ----------------------------------------------------------
resource "aws_ecr_repository" "agent" {
  name                 = "${var.project_name}-agent"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "${var.project_name}-agent" }
}

resource "aws_ecr_lifecycle_policy" "agent" {
  repository = aws_ecr_repository.agent.name

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
# Build and push Docker image
# ----------------------------------------------------------
resource "null_resource" "agent_image" {
  triggers = {
    dockerfile_hash = filemd5("${path.module}/docker/Dockerfile")
    handler_hash    = filemd5("${path.module}/docker/handler.py")
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws ecr get-login-password --region ${var.aws_region} | \
        docker login --username AWS --password-stdin ${aws_ecr_repository.agent.repository_url}
      docker build --platform linux/amd64 \
        -t ${aws_ecr_repository.agent.repository_url}:latest \
        ${path.module}/docker
      docker push ${aws_ecr_repository.agent.repository_url}:latest
    EOT
  }

  depends_on = [aws_ecr_repository.agent]
}

# ----------------------------------------------------------
# IAM Role
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

resource "aws_iam_role" "agent" {
  name               = "${var.project_name}-agent-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "agent_vpc" {
  role       = aws_iam_role.agent.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "agent_inline" {
  name = "${var.project_name}-agent-inline"
  role = aws_iam_role.agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockInvokeEmbeddingAndLLM"
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = [
          "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.bedrock_embedding_model_id}",
          "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.bedrock_llm_model_id}"
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
        Resource = [aws_ecr_repository.agent.arn]
      }
    ]
  })
}

# ----------------------------------------------------------
# Security Group  (reuse vectorizer SG — same egress rules)
# The agent Lambda needs to reach Elastic (PrivateLink) and Bedrock (NAT)
# ----------------------------------------------------------
resource "aws_security_group" "agent_lambda" {
  name        = "${var.project_name}-agent-lambda-sg"
  description = "Outbound-only SG for agent Lambda"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-agent-lambda-sg" }
}

# Add agent SG as an ingress source to Elastic PrivateLink SG
# (handled by the private_link module receiving the SG ID from vectorizer)

# ----------------------------------------------------------
# CloudWatch Log Group
# ----------------------------------------------------------
resource "aws_cloudwatch_log_group" "agent" {
  name              = "/aws/lambda/${var.project_name}-agent"
  retention_in_days = 14
}

# ----------------------------------------------------------
# Lambda Function
# ----------------------------------------------------------
resource "aws_lambda_function" "agent" {
  function_name = "${var.project_name}-agent"
  description   = "RAG agent — similarity search in Elastic + Bedrock LLM response"
  role          = aws_iam_role.agent.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.agent.repository_url}:latest"
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.agent_lambda.id]
  }

  environment {
    variables = {
      ELASTICSEARCH_ENDPOINT  = var.elasticsearch_endpoint
      ELASTIC_SECRET_NAME     = var.elasticsearch_connection_secret
      ELASTIC_INDEX_NAME      = var.elastic_index_name
      BEDROCK_EMBEDDING_MODEL = var.bedrock_embedding_model_id
      BEDROCK_LLM_MODEL       = var.bedrock_llm_model_id
      AWS_REGION_NAME         = var.aws_region
    }
  }

  depends_on = [
    null_resource.agent_image,
    aws_cloudwatch_log_group.agent,
    aws_iam_role_policy_attachment.agent_vpc
  ]

  tags = { Name = "${var.project_name}-agent" }
}
