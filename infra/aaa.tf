##################################################
# GLOBAL CONFIG
##################################################
terraform {
  required_version = ">=1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.primary_region
  alias  = "primary"
}

provider "aws" {
  region = var.secondary_region
  alias  = "secondary"
}

##################################################
# VARIABLES
##################################################
variable "project_name" { default = "multi-region-app" }
variable "primary_region" { default = "us-east-1" }
variable "secondary_region" { default = "us-east-2" }
variable "db_username" { default = "adminuser" }
variable "db_password" { default = "YourSecurePassword123!" }
variable "instance_type" { default = "t3.micro" }
variable "ami_primary" { default = "ami-0360c520857e3138f" }
variable "ami_secondary" { default = "ami-0cfde0ea8edd312d4" }
# variable "domain_name" { default = "example.com" }

##################################################
# PRIMARY REGION (us-east-1)
##################################################

# --- VPC ---
resource "aws_vpc" "primary_vpc" {
  provider             = aws.primary
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "${var.project_name}-primary-vpc" }
}

# --- SUBNETS (2x Public, 2x Private) ---
resource "aws_subnet" "primary_public_a" {
  provider                = aws.primary
  vpc_id                  = aws_vpc.primary_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.primary_region}a"
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-primary-public-a" }
}

resource "aws_subnet" "primary_public_b" {
  provider                = aws.primary
  vpc_id                  = aws_vpc.primary_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.primary_region}b"
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-primary-public-b" }
}

resource "aws_subnet" "primary_private_a" {
  provider          = aws.primary
  vpc_id            = aws_vpc.primary_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.primary_region}a"
  tags              = { Name = "${var.project_name}-primary-private-a" }
}

resource "aws_subnet" "primary_private_b" {
  provider          = aws.primary
  vpc_id            = aws_vpc.primary_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "${var.primary_region}b"
  tags              = { Name = "${var.project_name}-primary-private-b" }
}

# --- INTERNET GATEWAY / ROUTE TABLES ---
resource "aws_internet_gateway" "primary_igw" {
  provider = aws.primary
  vpc_id   = aws_vpc.primary_vpc.id
}

resource "aws_route_table" "primary_public_rt" {
  provider = aws.primary
  vpc_id   = aws_vpc.primary_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.primary_igw.id
  }
}

resource "aws_route_table_association" "primary_public_a_assoc" {
  provider       = aws.primary
  subnet_id      = aws_subnet.primary_public_a.id
  route_table_id = aws_route_table.primary_public_rt.id
}

resource "aws_route_table_association" "primary_public_b_assoc" {
  provider       = aws.primary
  subnet_id      = aws_subnet.primary_public_b.id
  route_table_id = aws_route_table.primary_public_rt.id
}

# --- SECURITY GROUP ---
resource "aws_security_group" "primary_sg" {
  provider = aws.primary
  vpc_id   = aws_vpc.primary_vpc.id
  name     = "${var.project_name}-primary-sg"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16", "10.1.0.0/16"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- IAM ROLE FOR EC2 ---
resource "aws_iam_role" "ec2_role" {
  name               = "${var.project_name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ec2_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_dynamodb" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

##################################################
# RDS GLOBAL DATABASE (Active-Active)
##################################################

# Primary Cluster
resource "aws_rds_global_cluster" "global_db" {
  provider                  = aws.primary
  global_cluster_identifier = "${var.project_name}-global-cluster"
  engine                    = "aurora-postgresql"
  engine_version            = "15.4"
  database_name             = "appdb"
}

resource "aws_db_subnet_group" "primary_db_subnet" {
  provider   = aws.primary
  name       = "${var.project_name}-primary-dbsubnet"
  subnet_ids = [aws_subnet.primary_private_a.id, aws_subnet.primary_private_b.id]
}

resource "aws_rds_cluster" "primary_cluster" {
  provider                     = aws.primary
  cluster_identifier           = "${var.project_name}-primary-cluster"
  engine                       = "aurora-postgresql"
  engine_version               = "15.4"
  database_name                = "appdb"
  master_username              = var.db_username
  master_password              = var.db_password
  db_subnet_group_name         = aws_db_subnet_group.primary_db_subnet.name
  vpc_security_group_ids       = [aws_security_group.primary_sg.id]
  skip_final_snapshot          = true
  global_cluster_identifier    = aws_rds_global_cluster.global_db.id
  backup_retention_period      = 7
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "mon:04:00-mon:05:00"
}

resource "aws_rds_cluster_instance" "primary_instance_1" {
  provider            = aws.primary
  identifier          = "${var.project_name}-primary-instance-1"
  cluster_identifier  = aws_rds_cluster.primary_cluster.id
  instance_class      = "db.r5.large"
  engine              = "aurora-postgresql"
  publicly_accessible = false
}

resource "aws_rds_cluster_instance" "primary_instance_2" {
  provider            = aws.primary
  identifier          = "${var.project_name}-primary-instance-2"
  cluster_identifier  = aws_rds_cluster.primary_cluster.id
  instance_class      = "db.r5.large"
  engine              = "aurora-postgresql"
  publicly_accessible = false
}

# --- EC2 BACKEND + ALB ---

# resource "aws_launch_template" "primary_backend" {
#   provider      = aws.primary
#   name_prefix   = "${var.project_name}-primary-backend"
#   image_id      = var.ami_primary
#   instance_type = var.instance_type
#   iam_instance_profile {
#     name = aws_iam_instance_profile.ec2_profile.name
#   }
#   vpc_security_group_ids = [aws_security_group.primary_sg.id]

#   user_data = base64encode(<<EOF
# #!/bin/bash
# sudo apt update -y
# sudo apt install -y nginx
# cat > /var/www/html/index.html <<HTML
# <!DOCTYPE html>
# <html>
# <head><title>Multi-Region App</title></head>
# <body>
#   <h1>Primary Region (US-EAST-1)</h1>
#   <p>Instance: $(hostname)</p>
#   <p>Region: ${var.primary_region}</p>
#   <p>Status: ACTIVE</p>
# </body>
# </html>
# HTML
# sudo systemctl restart nginx
# EOF
#   )



# }

# resource "aws_lb" "primary_alb" {
#   provider           = aws.primary
#   name               = "${var.project_name}-primary-alb"
#   internal           = false
#   load_balancer_type = "application"
#   subnets            = [aws_subnet.primary_public_a.id, aws_subnet.primary_public_b.id]
#   security_groups    = [aws_security_group.primary_sg.id]
# }

# resource "aws_lb_target_group" "primary_tg" {
#   provider = aws.primary
#   name     = "${var.project_name}-primary-tg"
#   port     = 80
#   protocol = "HTTP"
#   vpc_id   = aws_vpc.primary_vpc.id

#   health_check {
#     enabled             = true
#     healthy_threshold   = 2
#     interval            = 30
#     path                = "/"
#     port                = "traffic-port"
#     protocol            = "HTTP"
#     timeout             = 5
#     unhealthy_threshold = 2
#   }
# }

# resource "aws_lb_listener" "primary_listener" {
#   provider          = aws.primary
#   load_balancer_arn = aws_lb.primary_alb.arn
#   port              = 5000
#   protocol          = "HTTP"
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.primary_tg.arn
#   }
# }

# resource "aws_autoscaling_group" "primary_asg" {
#   provider         = aws.primary
#   desired_capacity = 2
#   max_size         = 5
#   min_size         = 2
#   launch_template {
#     id      = aws_launch_template.primary_backend.id
#     version = "$Latest"
#   }
#   vpc_zone_identifier = [aws_subnet.primary_public_a.id, aws_subnet.primary_public_b.id]
#   target_group_arns   = [aws_lb_target_group.primary_tg.arn]
#   depends_on          = [aws_lb_listener.primary_listener]

#   tag {
#     key                 = "Name"
#     value               = "${var.project_name}-primary-instance"
#     propagate_at_launch = true
#   }
# }

##################################################
# SECONDARY REGION (us-west-2)
##################################################

# --- VPC / SUBNETS ---
resource "aws_vpc" "secondary_vpc" {
  provider             = aws.secondary
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "${var.project_name}-secondary-vpc" }
}

resource "aws_subnet" "secondary_public_a" {
  provider                = aws.secondary
  vpc_id                  = aws_vpc.secondary_vpc.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "${var.secondary_region}a"
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-secondary-public-a" }
}

resource "aws_subnet" "secondary_public_b" {
  provider                = aws.secondary
  vpc_id                  = aws_vpc.secondary_vpc.id
  cidr_block              = "10.1.2.0/24"
  availability_zone       = "${var.secondary_region}b"
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-secondary-public-b" }
}

resource "aws_subnet" "secondary_private_a" {
  provider          = aws.secondary
  vpc_id            = aws_vpc.secondary_vpc.id
  cidr_block        = "10.1.3.0/24"
  availability_zone = "${var.secondary_region}a"
  tags              = { Name = "${var.project_name}-secondary-private-a" }
}

resource "aws_subnet" "secondary_private_b" {
  provider          = aws.secondary
  vpc_id            = aws_vpc.secondary_vpc.id
  cidr_block        = "10.1.4.0/24"
  availability_zone = "${var.secondary_region}b"
  tags              = { Name = "${var.project_name}-secondary-private-b" }
}

resource "aws_internet_gateway" "secondary_igw" {
  provider = aws.secondary
  vpc_id   = aws_vpc.secondary_vpc.id
}

resource "aws_route_table" "secondary_rt" {
  provider = aws.secondary
  vpc_id   = aws_vpc.secondary_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.secondary_igw.id
  }
}

resource "aws_route_table_association" "secondary_assoc_a" {
  provider       = aws.secondary
  subnet_id      = aws_subnet.secondary_public_a.id
  route_table_id = aws_route_table.secondary_rt.id
}

resource "aws_route_table_association" "secondary_assoc_b" {
  provider       = aws.secondary
  subnet_id      = aws_subnet.secondary_public_b.id
  route_table_id = aws_route_table.secondary_rt.id
}

resource "aws_security_group" "secondary_sg" {
  provider = aws.secondary
  vpc_id   = aws_vpc.secondary_vpc.id
  name     = "${var.project_name}-secondary-sg"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16", "10.1.0.0/16"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- RDS Secondary Cluster ---
resource "aws_db_subnet_group" "secondary_db_subnet" {
  provider   = aws.secondary
  name       = "${var.project_name}-secondary-dbsubnet"
  subnet_ids = [aws_subnet.secondary_private_a.id, aws_subnet.secondary_private_b.id]
}

resource "aws_rds_cluster" "secondary_cluster" {
  provider                  = aws.secondary
  cluster_identifier        = "${var.project_name}-secondary-cluster"
  engine                    = "aurora-postgresql"
  engine_version            = "15.4"
  db_subnet_group_name      = aws_db_subnet_group.secondary_db_subnet.name
  vpc_security_group_ids    = [aws_security_group.secondary_sg.id]
  skip_final_snapshot       = true
  global_cluster_identifier = aws_rds_global_cluster.global_db.id
  depends_on                = [aws_rds_cluster_instance.primary_instance_1]
}

resource "aws_rds_cluster_instance" "secondary_instance_1" {
  provider            = aws.secondary
  identifier          = "${var.project_name}-secondary-instance-1"
  cluster_identifier  = aws_rds_cluster.secondary_cluster.id
  instance_class      = "db.r5.large"
  engine              = "aurora-postgresql"
  publicly_accessible = false
}

resource "aws_rds_cluster_instance" "secondary_instance_2" {
  provider            = aws.secondary
  identifier          = "${var.project_name}-secondary-instance-2"
  cluster_identifier  = aws_rds_cluster.secondary_cluster.id
  instance_class      = "db.r5.large"
  engine              = "aurora-postgresql"
  publicly_accessible = false
}

# --- EC2 + ALB ---

# resource "aws_launch_template" "secondary_backend" {
#   provider               = aws.secondary
#   name_prefix            = "${var.project_name}-secondary-backend"
#   image_id               = var.ami_secondary
#   instance_type          = var.instance_type
#   vpc_security_group_ids = [aws_security_group.secondary_sg.id]
#   iam_instance_profile {
#     name = aws_iam_instance_profile.ec2_profile.name
#   }

#   user_data = base64encode(<<EOF
# #!/bin/bash
# sudo apt update -y
# sudo apt install -y nginx
# cat > /var/www/html/index.html <<HTML
# <!DOCTYPE html>
# <html>
# <head><title>Multi-Region App</title></head>
# <body>
#   <h1>Secondary Region (US-WEST-2)</h1>
#   <p>Instance: $(hostname)</p>
#   <p>Region: ${var.secondary_region}</p>
#   <p>Status: ACTIVE</p>
# </body>
# </html>
# HTML
# sudo systemctl restart nginx
# EOF
#   )
# }

# resource "aws_lb" "secondary_alb" {
#   provider           = aws.secondary
#   name               = "${var.project_name}-secondary-alb"
#   internal           = false
#   load_balancer_type = "application"
#   subnets            = [aws_subnet.secondary_public_a.id, aws_subnet.secondary_public_b.id]
#   security_groups    = [aws_security_group.secondary_sg.id]
# }

# resource "aws_lb_target_group" "secondary_tg" {
#   provider = aws.secondary
#   name     = "${var.project_name}-secondary-tg"
#   port     = 80
#   protocol = "HTTP"
#   vpc_id   = aws_vpc.secondary_vpc.id

#   health_check {
#     enabled             = true
#     healthy_threshold   = 2
#     interval            = 30
#     path                = "/"
#     port                = "traffic-port"
#     protocol            = "HTTP"
#     timeout             = 5
#     unhealthy_threshold = 2
#   }
# }

# resource "aws_lb_listener" "secondary_listener" {
#   provider          = aws.secondary
#   load_balancer_arn = aws_lb.secondary_alb.arn
#   port              = 5000
#   protocol          = "HTTP"
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.secondary_tg.arn
#   }
# }

# resource "aws_autoscaling_group" "secondary_asg" {
#   provider         = aws.secondary
#   desired_capacity = 2
#   max_size         = 5
#   min_size         = 2
#   launch_template {
#     id      = aws_launch_template.secondary_backend.id
#     version = "$Latest"
#   }
#   vpc_zone_identifier = [aws_subnet.secondary_public_a.id, aws_subnet.secondary_public_b.id]
#   target_group_arns   = [aws_lb_target_group.secondary_tg.arn]
#   depends_on          = [aws_lb_listener.secondary_listener]

#   tag {
#     key                 = "Name"
#     value               = "${var.project_name}-secondary-instance"
#     propagate_at_launch = true
#   }
# }

##################################################
# DYNAMODB GLOBAL TABLE (Session Storage)
##################################################

resource "aws_dynamodb_table" "session_table" {
  provider         = aws.primary
  name             = "${var.project_name}-sessions"
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "sessionId"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "sessionId"
    type = "S"
  }

  replica {
    region_name = var.secondary_region
  }

  tags = {
    Name = "${var.project_name}-sessions"
  }
}

##################################################
# ROUTE 53 (Global Traffic Management)
##################################################

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

##################################################
# S3 CROSS-REGION REPLICATION (Static Assets)
##################################################

resource "aws_s3_bucket" "primary_assets" {
  provider = aws.primary
  bucket   = "${var.project_name}-assets-primary"
}

resource "aws_s3_bucket" "secondary_assets" {
  provider = aws.secondary
  bucket   = "${var.project_name}-assets-secondary"
}

resource "aws_s3_bucket_versioning" "primary_versioning" {
  provider = aws.primary
  bucket   = aws_s3_bucket.primary_assets.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "secondary_versioning" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.secondary_assets.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_role" "replication" {
  name = "${var.project_name}-s3-replication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "replication" {
  role = aws_iam_role.replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.primary_assets.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl"
        ]
        Resource = [
          "${aws_s3_bucket.primary_assets.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete"
        ]
        Resource = [
          "${aws_s3_bucket.secondary_assets.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "primary_to_secondary" {
  provider = aws.primary
  bucket   = aws_s3_bucket.primary_assets.id
  role     = aws_iam_role.replication.arn

  rule {
    id     = "replicate-all"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.secondary_assets.arn
      storage_class = "STANDARD"
    }
  }

  depends_on = [aws_s3_bucket_versioning.primary_versioning]
}

##################################################
# OUTPUTS
##################################################
# output "route53_endpoint" {
#   value       = "app.${var.domain_name}"
#   description = "Global endpoint for the application"
# }

# output "primary_alb_dns" {
#   value       = aws_lb.primary_alb.dns_name
#   description = "Primary region ALB DNS"
# }

# output "secondary_alb_dns" {
#   value       = aws_lb.secondary_alb.dns_name
#   description = "Secondary region ALB DNS"
# }

output "primary_db_endpoint" {
  value       = aws_rds_cluster.primary_cluster.endpoint
  description = "Primary Aurora cluster endpoint"
}

output "secondary_db_endpoint" {
  value       = aws_rds_cluster.secondary_cluster.endpoint
  description = "Secondary Aurora cluster endpoint"
}

output "dynamodb_table" {
  value       = aws_dynamodb_table.session_table.name
  description = "Global DynamoDB table for sessions"
}

output "s3_primary_bucket" {
  value       = aws_s3_bucket.primary_assets.bucket
  description = "Primary S3 bucket for assets"
}

output "s3_secondary_bucket" {
  value       = aws_s3_bucket.secondary_assets.bucket
  description = "Secondary S3 bucket for assets"
}
