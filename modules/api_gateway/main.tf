# =============================================================
# API Gateway Module
# Creates: HTTP API (API GW v2), Lambda integration,
#          POST /agent route, $default stage with auto-deploy,
#          CloudWatch log group, Lambda permission
# =============================================================

# ----------------------------------------------------------
# CloudWatch Log Group for API Gateway access logs
# ----------------------------------------------------------
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.project_name}-api"
  retention_in_days = 14
}

# ----------------------------------------------------------
# HTTP API
# ----------------------------------------------------------
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
  description   = "HTTP API for the RAG agent"

  cors_configuration {
    allow_headers = ["Content-Type", "Authorization"]
    allow_methods = ["POST", "OPTIONS"]
    allow_origins = ["*"]
    max_age       = 300
  }

  tags = { Name = "${var.project_name}-api" }
}

# ----------------------------------------------------------
# Lambda Integration
# ----------------------------------------------------------
resource "aws_apigatewayv2_integration" "agent" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.lambda_agent_invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 29000  # API GW max is 29s; Lambda timeout is set separately
}

# ----------------------------------------------------------
# Routes
# ----------------------------------------------------------
resource "aws_apigatewayv2_route" "agent_post" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /agent"
  target    = "integrations/${aws_apigatewayv2_integration.agent.id}"
}

# Health-check route
resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.agent.id}"
}

# ----------------------------------------------------------
# $default stage with auto-deploy and access logging
# ----------------------------------------------------------
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
  }

  default_route_settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }

  tags = { Name = "${var.project_name}-api-default-stage" }
}

# ----------------------------------------------------------
# Allow API Gateway to invoke the Lambda
# ----------------------------------------------------------
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_agent_arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
