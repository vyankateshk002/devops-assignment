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

  # Backend configuration (Local state by default for ease of testing;
  # can be switched to S3 backend for team/CI/CD deployments)
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "devops-assignment/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  # }
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
