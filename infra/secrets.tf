# -------------------------------------------------------------
# Secrets for DB creds with replication in secondary region
# -------------------------------------------------------------
resource "aws_secretsmanager_secret" "app_secret" {
  name     = var.app_secret_name
  provider = aws.primary

  # Enable replication to secondary region
  replica {
    region = var.secondary_region
  }

  tags = {
    Name = "${var.project_name}-app-secret"
  }
}


resource "aws_secretsmanager_secret_version" "app_secret_value" {
  secret_id = aws_secretsmanager_secret.app_secret.id
  secret_string = jsonencode({
    db_username                   = var.db_username
    db_password                   = var.db_password
    db_global_cluster_endpoint    = aws_rds_global_cluster.global_db.endpoint
    db_primary_cluster_endpoint   = aws_rds_cluster.primary_cluster.endpoint
    db_secondary_cluster_endpoint = aws_rds_cluster.secondary_cluster.endpoint
    db_name                       = var.db_name

    cloudfront_url = "https://${aws_cloudfront_distribution.cdn.domain_name}"

    main_s3_bucket      = aws_s3_bucket.primary_assets.bucket
    secondary_s3_bucket = aws_s3_bucket.secondary_assets.bucket

  })
}
