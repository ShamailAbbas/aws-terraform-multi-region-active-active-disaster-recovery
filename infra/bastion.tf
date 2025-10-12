# -----------------------
# Key Pair
# -----------------------
resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ec2_key" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.ec2_key.public_key_openssh
}

# Optional: Save private key locally
resource "local_file" "private_key" {
  content         = tls_private_key.ec2_key.private_key_pem
  filename        = "${path.module}/../ssh-key.pem"
  file_permission = "0600"
}

# -----------------------
# Bastion host EC2 Instance
# -----------------------
resource "aws_instance" "primary_bastion" {
  ami                         = var.ami_primary
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.primary_public_a.id
  vpc_security_group_ids      = [aws_security_group.primary_sg.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.ec2_key.key_name
  tags                        = { Name = "${var.project_name}-bastion" }
}

resource "aws_instance" "secondary_bastion" {
  ami                         = var.ami_secondary
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.secondary_public_a.id
  vpc_security_group_ids      = [aws_security_group.secondary_sg.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.ec2_key.key_name
  tags                        = { Name = "${var.project_name}-bastion" }


}
