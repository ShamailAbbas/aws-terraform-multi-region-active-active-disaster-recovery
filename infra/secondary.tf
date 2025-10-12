

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

resource "aws_subnet" "secondary_private_c" {
  provider          = aws.secondary
  vpc_id            = aws_vpc.secondary_vpc.id
  cidr_block        = "10.1.5.0/24"
  availability_zone = "${var.secondary_region}a"
  tags              = { Name = "${var.project_name}-secondary-private-c" }
}

resource "aws_subnet" "secondary_private_d" {
  provider          = aws.secondary
  vpc_id            = aws_vpc.secondary_vpc.id
  cidr_block        = "10.1.6.0/24"
  availability_zone = "${var.secondary_region}b"
  tags              = { Name = "${var.project_name}-secondary-private-d" }
}

# --- INTERNET GATEWAY / ROUTE TABLES ---

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


# SECONDARY NAT GATEWAY
resource "aws_eip" "secondary_nat" {
  provider = aws.secondary
  domain   = "vpc"
}

resource "aws_nat_gateway" "secondary_nat" {
  provider      = aws.secondary
  allocation_id = aws_eip.secondary_nat.id
  subnet_id     = aws_subnet.secondary_public_a.id

  tags = {
    Name = "${var.project_name}-secondary-nat"
  }
}

# Update secondary private route table to use NAT
resource "aws_route" "secondary_private_nat" {
  provider               = aws.secondary
  route_table_id         = aws_route_table.secondary_private_rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.secondary_nat.id
}


# --- PRIVATE ROUTE TABLE ---
resource "aws_route_table" "secondary_private_rt" {
  provider = aws.secondary
  vpc_id   = aws_vpc.secondary_vpc.id
  tags     = { Name = "${var.project_name}-secondary-private-rt" }
}

# --- Associate with private subnets ---
resource "aws_route_table_association" "secondary_private_a_assoc" {
  provider       = aws.secondary
  subnet_id      = aws_subnet.secondary_private_a.id
  route_table_id = aws_route_table.secondary_private_rt.id
}

resource "aws_route_table_association" "secondary_private_b_assoc" {
  provider       = aws.secondary
  subnet_id      = aws_subnet.secondary_private_b.id
  route_table_id = aws_route_table.secondary_private_rt.id
}
resource "aws_route_table_association" "secondary_private_c_assoc" {
  provider       = aws.secondary
  subnet_id      = aws_subnet.secondary_private_c.id
  route_table_id = aws_route_table.secondary_private_rt.id
}

resource "aws_route_table_association" "secondary_private_d_assoc" {
  provider       = aws.secondary
  subnet_id      = aws_subnet.secondary_private_d.id
  route_table_id = aws_route_table.secondary_private_rt.id
}


# --- SECURITY GROUP ---

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
  subnet_ids = [aws_subnet.secondary_private_c.id, aws_subnet.secondary_private_d.id]
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

  enable_global_write_forwarding = true

  lifecycle {
    ignore_changes = [
      replication_source_identifier,
      engine_version,
      master_username,
      storage_encrypted,
      availability_zones,
    ]
  }

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
  key_name = aws_key_pair.secondary_region_ec2_key.key_name

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
APP_SECRET_NAME=${aws_secretsmanager_secret.app_secret.name}

ENV

# Install Node.js dependencies
npm install

# install pm2
sudo npm install -g pm2

# Start Node.js app with PM2
pm2 start npm --name nodeapp -- start
pm2 save
sudo pm2 startup systemd -u ubuntu --hp /home/ubuntu

EOF
  )

  depends_on = [aws_s3_bucket.primary_assets, aws_s3_bucket.secondary_assets, aws_secretsmanager_secret.app_secret, aws_rds_cluster.primary_cluster, aws_rds_cluster.secondary_cluster]

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
  vpc_zone_identifier = [aws_subnet.secondary_private_a.id,
  aws_subnet.secondary_private_b.id]
  target_group_arns = [aws_lb_target_group.secondary_tg.arn]
  depends_on        = [aws_lb_listener.secondary_listener]

  tag {
    key                 = "Name"
    value               = "${var.project_name}-secondary-instance"
    propagate_at_launch = true
  }
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




# -----------------------
# Key Pair
# -----------------------
resource "tls_private_key" "secondary_region_ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "secondary_region_ec2_key" {
  key_name   = "${var.project_name}-secondary-region-ssh-key"
  public_key = tls_private_key.secondary_region_ec2_key.public_key_openssh
}

# Optional: Save private key locally
resource "local_file" "private_key" {
  content         = tls_private_key.secondary_region_ec2_key.private_key_pem
  filename        = "${path.module}/../secondary-region-ssh-key.pem"
  file_permission = "0600"
}

# -----------------------
# Bastion host EC2 Instance
# -----------------------
resource "aws_instance" "bastion" {
  ami                         = var.ami_secondary
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.secondary_public_a.id
  vpc_security_group_ids      = [aws_security_group.secondary_sg.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.secondary_region_ec2_key.key_name
  tags                        = { Name = "${var.project_name}-bastion" }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get upgrade -y
              apt-get install git curl build-essential -y
              curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
              sudo apt-get install -y nodejs
              EOF
}
