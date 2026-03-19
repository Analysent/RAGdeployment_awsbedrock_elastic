output "vpc_endpoint_id" {
  description = "VPC endpoint ID for Elastic Cloud PrivateLink"
  value       = aws_vpc_endpoint.elastic.id
}

output "vpc_endpoint_dns_name" {
  description = "DNS name of the Elastic VPC endpoint"
  value       = aws_vpc_endpoint.elastic.dns_entry[0].dns_name
}

output "private_hosted_zone_id" {
  description = "Route53 private hosted zone ID"
  value       = aws_route53_zone.elastic_private.zone_id
}

output "elastic_endpoint_security_group_id" {
  description = "Security group ID attached to the Elastic VPC endpoint"
  value       = aws_security_group.elastic_endpoint.id
}
