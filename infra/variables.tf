##################################################
# VARIABLES
##################################################
variable "project_name" { default = "multi-region-app" }
variable "primary_region" { default = "us-east-1" }
variable "secondary_region" { default = "us-east-2" }
variable "db_name" { default = "appdb" }
variable "db_username" { default = "adminuser" }
variable "db_password" { default = "YourSecurePassword123!" }
variable "instance_type" { default = "t3.micro" }
variable "ami_primary" { default = "ami-0360c520857e3138f" }
variable "ami_secondary" { default = "ami-0cfde0ea8edd312d4" }
variable "db_secret_name" { default = "database-creds-secret" }

