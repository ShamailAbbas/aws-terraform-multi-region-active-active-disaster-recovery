##################################################
# ROUTE 53 (Global Traffic Management)
##################################################

# variable "domain_name" { default = "example.com" }

# data "aws_route53_zone" "main" {
#   name         = var.domain_name
#   private_zone = false
# }

# # Health Check for Primary
# resource "aws_route53_health_check" "primary" {
#   fqdn              = aws_lb.primary_alb.dns_name
#   port              = 80
#   type              = "HTTP"
#   resource_path     = "/"
#   failure_threshold = 3
#   request_interval  = 30

#   tags = {
#     Name = "${var.project_name}-primary-health"
#   }
# }

# # Health Check for Secondary
# resource "aws_route53_health_check" "secondary" {
#   fqdn              = aws_lb.secondary_alb.dns_name
#   port              = 80
#   type              = "HTTP"
#   resource_path     = "/"
#   failure_threshold = 3
#   request_interval  = 30

#   tags = {
#     Name = "${var.project_name}-secondary-health"
#   }
# }

# # Latency-based routing for active-active
# resource "aws_route53_record" "primary" {
#   zone_id        = data.aws_route53_zone.main.zone_id
#   name           = "app.${var.domain_name}"
#   type           = "A"
#   set_identifier = "primary"

#   alias {
#     name                   = aws_lb.primary_alb.dns_name
#     zone_id                = aws_lb.primary_alb.zone_id
#     evaluate_target_health = true
#   }

#   latency_routing_policy {
#     region = var.primary_region
#   }

#   health_check_id = aws_route53_health_check.primary.id
# }

# resource "aws_route53_record" "secondary" {
#   zone_id        = data.aws_route53_zone.main.zone_id
#   name           = "app.${var.domain_name}"
#   type           = "A"
#   set_identifier = "secondary"

#   alias {
#     name                   = aws_lb.secondary_alb.dns_name
#     zone_id                = aws_lb.secondary_alb.zone_id
#     evaluate_target_health = true
#   }

#   latency_routing_policy {
#     region = var.secondary_region
#   }

#   health_check_id = aws_route53_health_check.secondary.id
# }


