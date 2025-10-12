# --------------------------------------
# Shared SSH Key (generated once)
# --------------------------------------
resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Save the private key locally
resource "local_file" "private_key" {
  content         = tls_private_key.ec2_key.private_key_pem
  filename        = "${path.module}/../ssh-key.pem"
  file_permission = "0600"
}

# --------------------------------------
# Register key in PRIMARY region
# --------------------------------------
resource "aws_key_pair" "primary_key" {
  provider   = aws.primary
  key_name   = "${var.project_name}-key-primary"
  public_key = tls_private_key.ec2_key.public_key_openssh
}

# --------------------------------------
# Register key in SECONDARY region
# --------------------------------------
resource "aws_key_pair" "secondary_key" {
  provider   = aws.secondary
  key_name   = "${var.project_name}-key-secondary"
  public_key = tls_private_key.ec2_key.public_key_openssh
}

# --------------------------------------
# Bastion instances
# --------------------------------------
resource "aws_instance" "primary_bastion" {
  provider                    = aws.primary
  ami                         = var.ami_primary
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.primary_public_a.id
  vpc_security_group_ids      = [aws_security_group.primary_sg.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.primary_key.key_name
  tags                        = { Name = "${var.project_name}-bastion-primary" }
}

resource "aws_instance" "secondary_bastion" {
  provider                    = aws.secondary
  ami                         = var.ami_secondary
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.secondary_public_a.id
  vpc_security_group_ids      = [aws_security_group.secondary_sg.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.secondary_key.key_name
  tags                        = { Name = "${var.project_name}-bastion-secondary" }
}
