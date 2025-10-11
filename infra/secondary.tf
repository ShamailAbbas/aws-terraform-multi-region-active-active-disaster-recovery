

##################################################
# SECONDARY REGION (us-east-2)
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

resource "aws_launch_template" "secondary_backend" {
  provider               = aws.secondary
  name_prefix            = "${var.project_name}-secondary-backend"
  image_id               = var.ami_secondary
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.secondary_sg.id]
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

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
REGION=us-east-2
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

resource "aws_lb" "secondary_alb" {
  provider           = aws.secondary
  name               = "${var.project_name}-secondary-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.secondary_public_a.id, aws_subnet.secondary_public_b.id]
  security_groups    = [aws_security_group.secondary_sg.id]
}

resource "aws_lb_target_group" "secondary_tg" {
  provider = aws.secondary
  name     = "${var.project_name}-secondary-tg"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_vpc.secondary_vpc.id

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

resource "aws_lb_listener" "secondary_listener" {
  provider          = aws.secondary
  load_balancer_arn = aws_lb.secondary_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.secondary_tg.arn
  }
}

resource "aws_autoscaling_group" "secondary_asg" {
  provider         = aws.secondary
  desired_capacity = 2
  max_size         = 5
  min_size         = 1
  launch_template {
    id      = aws_launch_template.secondary_backend.id
    version = "$Latest"
  }
  vpc_zone_identifier = [aws_subnet.secondary_public_a.id, aws_subnet.secondary_public_b.id]
  target_group_arns   = [aws_lb_target_group.secondary_tg.arn]
  depends_on          = [aws_lb_listener.secondary_listener]

  tag {
    key                 = "Name"
    value               = "${var.project_name}-secondary-instance"
    propagate_at_launch = true
  }
}


