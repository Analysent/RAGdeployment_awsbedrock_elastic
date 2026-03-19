variable "project_name" {
  type = string
}

variable "lambda_agent_arn" {
  description = "ARN of the agent Lambda function"
  type        = string
}

variable "lambda_agent_invoke_arn" {
  description = "Invoke ARN of the agent Lambda (used in integration)"
  type        = string
}

variable "aws_region" {
  type = string
}

variable "aws_account_id" {
  type = string
}
