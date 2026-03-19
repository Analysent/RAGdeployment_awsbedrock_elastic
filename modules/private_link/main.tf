# =============================================================
# Private Link Module
# Creates: VPC Interface Endpoint for Elastic Cloud,
#          security group, Route53 private hosted zone,
#          DNS CNAME records
# =============================================================

# ----------------------------------------------------------
# Security Group for the Elastic VPC endpoint
# ----------------------------------------------------------
resource "aws_security_group" "elastic_endpoint" {
  name        = "${var.project_name}-elastic-endpoint-sg"
  description = "Allow HTTPS from Lambda to Elastic Cloud PrivateLink endpoint"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTPS from Lambda functions"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [var.lambda_security_group_id]
  }

  ingress {
    description     = "Elastic transport port from Lambda"
    from_port       = 9243
    to_port         = 9243
    protocol        = "tcp"
    security_groups = [var.lambda_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-elastic-endpoint-sg" }
}

# ----------------------------------------------------------
# VPC Interface Endpoint → Elastic Cloud PrivateLink
# ----------------------------------------------------------
resource "aws_vpc_endpoint" "elastic" {
  vpc_id              = var.vpc_id
  service_name        = var.elastic_private_link_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.elastic_endpoint.id]
  private_dns_enabled = false # We manage DNS via Route53 below

  tags = { Name = "${var.project_name}-elastic-endpoint" }
}

# ----------------------------------------------------------
# Route53 Private Hosted Zone for Elastic DNS resolution
# Resolves <deployment-id>.{zone} → VPC endpoint DNS
# ----------------------------------------------------------
resource "aws_route53_zone" "elastic_private" {
  name    = var.elastic_private_link_zone_name
  comment = "Private zone for Elastic Cloud PrivateLink DNS resolution"

  vpc {
    vpc_id = var.vpc_id
  }

  tags = { Name = "${var.project_name}-elastic-private-zone" }
}

# Wildcard record: *.{zone} → VPC endpoint DNS (covers all deployment sub-domains)
resource "aws_route53_record" "elastic_wildcard" {
  zone_id = aws_route53_zone.elastic_private.zone_id
  name    = "*.${var.elastic_private_link_zone_name}"
  type    = "CNAME"
  ttl     = 60
  records = [aws_vpc_endpoint.elastic.dns_entry[0].dns_name]
}

# Specific record for this deployment ID
resource "aws_route53_record" "elastic_deployment" {
  zone_id = aws_route53_zone.elastic_private.zone_id
  name    = "${var.deployment_id}.${var.elastic_private_link_zone_name}"
  type    = "CNAME"
  ttl     = 60
  records = [aws_vpc_endpoint.elastic.dns_entry[0].dns_name]
}
