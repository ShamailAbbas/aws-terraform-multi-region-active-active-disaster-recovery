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

data "aws_caller_identity" "current" {}
