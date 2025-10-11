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
    from_port   = 5000
    to_port     = 5000
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
# --- EC2 S3 ACCESS POLICY ---
resource "aws_iam_policy" "ec2_s3_access" {
  name        = "${var.project_name}-ec2-s3-access"
  description = "EC2 read/write access to primary and secondary S3 buckets"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ],
        Resource = [
          aws_s3_bucket.primary_assets.arn,
          "${aws_s3_bucket.primary_assets.arn}/*",
          aws_s3_bucket.secondary_assets.arn,
          "${aws_s3_bucket.secondary_assets.arn}/*"
        ]
      },
      {
        Effect : "Allow",
        Action : [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ],
        Resource : ["arn:aws:secretsmanager:${var.primary_region}:${data.aws_caller_identity.current.account_id}:secret:${var.db_secret_name}-*",
          "arn:aws:secretsmanager:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:secret:${var.db_secret_name}-*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_s3_access_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_s3_access.arn
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
  database_name             = var.db_name
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
  database_name                = var.db_name
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

resource "aws_launch_template" "primary_backend" {
  provider      = aws.primary
  name_prefix   = "${var.project_name}-primary-backend"
  image_id      = var.ami_primary
  instance_type = var.instance_type
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }
  vpc_security_group_ids = [aws_security_group.primary_sg.id]

  user_data = base64encode(<<EOF
#!/bin/bash
# Update and install dependencies
sudo apt update -y
sudo apt install -y  git curl build-essential

# Install Node.js (latest LTS)
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs

# Clone the repository
cd /home/ubuntu
git clone https://github.com/ShamailAbbas/aws-terraform-multi-region-active-active-disaster-recovery.git
cd aws-terraform-multi-region-active-active-disaster-recovery/backend

# Create .env file with environment variables
cat > .env <<ENV
REGION=us-east-1
S3_BUCKET_PRIMARY=${aws_s3_bucket.primary_assets.bucket}
S3_BUCKET_SECONDARY=${aws_s3_bucket.secondary_assets.bucket}

ENV

# Install Node.js dependencies
npm install

# Start the Node.js backend app
npm start
EOF
  )


  depends_on = [aws_s3_bucket.primary_assets.bucket, aws_s3_bucket.secondary_assets.bucket]

}

resource "aws_lb" "primary_alb" {
  provider           = aws.primary
  name               = "${var.project_name}-primary-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.primary_public_a.id, aws_subnet.primary_public_b.id]
  security_groups    = [aws_security_group.primary_sg.id]
}

resource "aws_lb_target_group" "primary_tg" {
  provider = aws.primary
  name     = "${var.project_name}-primary-tg"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_vpc.primary_vpc.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "primary_listener" {
  provider          = aws.primary
  load_balancer_arn = aws_lb.primary_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.primary_tg.arn
  }
}

resource "aws_autoscaling_group" "primary_asg" {
  provider         = aws.primary
  desired_capacity = 2
  max_size         = 5
  min_size         = 2
  launch_template {
    id      = aws_launch_template.primary_backend.id
    version = "$Latest"
  }
  vpc_zone_identifier = [aws_subnet.primary_public_a.id, aws_subnet.primary_public_b.id]
  target_group_arns   = [aws_lb_target_group.primary_tg.arn]
  depends_on          = [aws_lb_listener.primary_listener]

  tag {
    key                 = "Name"
    value               = "${var.project_name}-primary-instance"
    propagate_at_launch = true
  }
}



# -------------------------------------------------------------
# Secrets for DB creds with replication in secondary region
# -------------------------------------------------------------
resource "aws_secretsmanager_secret" "db_secret" {
  name     = var.db_secret_name
  provider = aws.primary

  # Enable replication to secondary region
  replica {
    region = var.secondary_region
  }

  tags = {
    Name = "${var.project_name}-db-secret"
  }
}


resource "aws_secretsmanager_secret_version" "db_secret_value" {
  secret_id = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode({
    username                        = var.db_username
    password                        = var.db_password
    primary_cluster_writer_endpoint = aws_rds_cluster.primary_cluster.endpoint
    secondary_cluster_endpoint      = aws_rds_cluster.secondary_cluster.endpoint
    dbname                          = var.db_name
  })
}




####################################################################
# S3 in primary with CROSS-REGION REPLICATION  in secondary region
#####################################################################

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
