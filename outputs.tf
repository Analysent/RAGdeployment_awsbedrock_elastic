output "bucket_name" {
  description = "Name of the S3 data-source bucket — upload your PDFs/documents here"
  value       = module.data_source.bucket_id
}

output "invoke_url" {
  description = "API Gateway base URL — append /agent to POST questions"
  value       = module.api_gateway.invoke_url
}

output "agent_endpoint" {
  description = "Full endpoint URL for the RAG agent"
  value       = "${module.api_gateway.invoke_url}/agent"
}

output "vpc_id" {
  description = "ID of the VPC created for this deployment"
  value       = module.vpc.vpc_id
}

output "elastic_vpc_endpoint_id" {
  description = "VPC Endpoint ID for the Elastic Cloud PrivateLink connection"
  value       = module.private_link.vpc_endpoint_id
}

output "vectorizer_lambda_name" {
  description = "Name of the vectorizer Lambda function"
  value       = module.lambda_vectorizer.lambda_function_name
}

output "agent_lambda_name" {
  description = "Name of the agent Lambda function"
  value       = module.lambda_agent.lambda_function_name
}

output "example_curl" {
  description = "Example cURL command to test the agent endpoint"
  value       = <<-EOT
    curl -X POST ${module.api_gateway.invoke_url}/agent \
      -H "Content-Type: application/json" \
      -d '{"question": "What is cloud-native DevOps?"}'
  EOT
}
