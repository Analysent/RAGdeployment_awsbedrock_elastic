output "lambda_arn" {
  description = "ARN of the vectorizer Lambda function"
  value       = aws_lambda_function.vectorizer.arn
}

output "lambda_function_name" {
  description = "Name of the vectorizer Lambda function"
  value       = aws_lambda_function.vectorizer.function_name
}

output "lambda_security_group_id" {
  description = "Security group ID of the vectorizer Lambda (also used by agent Lambda)"
  value       = aws_security_group.vectorizer_lambda.id
}

output "ecr_repository_url" {
  description = "ECR repository URL for the vectorizer image"
  value       = aws_ecr_repository.vectorizer.repository_url
}
