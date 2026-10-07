terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # S3 Remote Backend for persistent CI/CD state
  backend "s3" {
    bucket  = "devops-assignment-tfstate-919519434135"
    key     = "devops-assignment/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = "DevOps-Assignment"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "Vyankatesh"
    }
  }
}
