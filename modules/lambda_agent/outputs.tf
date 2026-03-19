output "lambda_arn" {
  description = "ARN of the agent Lambda function"
  value       = aws_lambda_function.agent.arn
}

output "lambda_invoke_arn" {
  description = "Invoke ARN of the agent Lambda (used by API Gateway)"
  value       = aws_lambda_function.agent.invoke_arn
}

output "lambda_function_name" {
  description = "Name of the agent Lambda function"
  value       = aws_lambda_function.agent.function_name
}

output "lambda_security_group_id" {
  description = "Security group ID of the agent Lambda"
  value       = aws_security_group.agent_lambda.id
}
