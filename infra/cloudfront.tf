##################################################
# CLOUDFRONT DISTRIBUTION WITH FAILOVER
##################################################

# Create Origin Access Control for CloudFront
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${var.project_name}-oac"
  description                       = "Access control for CloudFront to access S3"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Primary Origin
locals {
  primary_origin_id   = "${var.project_name}-primary-origin"
  secondary_origin_id = "${var.project_name}-secondary-origin"
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  comment             = "${var.project_name} CDN with failover"
  default_root_object = "index.html"

  origin_group {
    origin_id = "origin-group-failover"

    failover_criteria {
      status_codes = [403, 404, 500, 502, 503, 504]
    }

    member {
      origin_id = local.primary_origin_id
    }

    member {
      origin_id = local.secondary_origin_id
    }
  }

  origin {
    domain_name              = aws_s3_bucket.primary_assets.bucket_regional_domain_name
    origin_id                = local.primary_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  origin {
    domain_name              = aws_s3_bucket.secondary_assets.bucket_regional_domain_name
    origin_id                = local.secondary_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    target_origin_id       = "origin-group-failover"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  depends_on = [
    aws_s3_bucket.primary_assets,
    aws_s3_bucket.secondary_assets
  ]
}

##################################################
# S3 BUCKET POLICIES TO ALLOW CLOUDFRONT ACCESS
##################################################

data "aws_cloudfront_distribution" "cdn" {
  id = aws_cloudfront_distribution.cdn.id
}

resource "aws_s3_bucket_policy" "primary_policy" {
  bucket = aws_s3_bucket.primary_assets.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowCloudFrontAccess",
        Effect = "Allow",
        Principal = {
          Service = "cloudfront.amazonaws.com"
        },
        Action   = ["s3:GetObject"],
        Resource = "${aws_s3_bucket.primary_assets.arn}/*",
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.cdn.arn
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_policy" "secondary_policy" {
  bucket = aws_s3_bucket.secondary_assets.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowCloudFrontAccess",
        Effect = "Allow",
        Principal = {
          Service = "cloudfront.amazonaws.com"
        },
        Action   = ["s3:GetObject"],
        Resource = "${aws_s3_bucket.secondary_assets.arn}/*",
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.cdn.arn
          }
        }
      }
    ]
  })
}



