
##################################################
# OUTPUTS
##################################################
# output "route53_endpoint" {
#   value       = "app.${var.domain_name}"
#   description = "Global endpoint for the application"
# }

output "primary_alb_dns" {
  value       = aws_lb.primary_alb.dns_name
  description = "Primary region ALB DNS"
}

output "secondary_alb_dns" {
  value       = aws_lb.secondary_alb.dns_name
  description = "Secondary region ALB DNS"
}

output "primary_db_endpoint" {
  value       = aws_rds_cluster.primary_cluster.endpoint
  description = "Primary Aurora cluster endpoint"
}

output "secondary_db_endpoint" {
  value       = aws_rds_cluster.secondary_cluster.endpoint
  description = "Secondary Aurora cluster endpoint"
}

output "db_secret_arn" {
  value       = aws_secretsmanager_secret.db_secret.arn
  description = "Secrets Manager ARN for DB credentials"
}

output "s3_primary_bucket" {
  value       = aws_s3_bucket.primary_assets.bucket
  description = "Primary S3 bucket for assets"
}

output "s3_secondary_bucket" {
  value       = aws_s3_bucket.secondary_assets.bucket
  description = "Secondary S3 bucket for assets"
}
