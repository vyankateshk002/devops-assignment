# Local values for common tags and naming
locals {
  common_tags = {
    Project     = "DevOps-Assignment"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Tier        = "Free-Tier-Optimized"
  }
}

# 1. Networking Module (VPC, Subnets, Route Tables, Internet Gateway, Free-Tier NAT Instance)
module "vpc" {
  source = "./modules/vpc"

  name_prefix              = var.name_prefix
  vpc_cidr                 = var.vpc_cidr
  availability_zones       = var.availability_zones
  public_subnet_cidrs      = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_db_subnet_cidrs  = var.private_db_subnet_cidrs
  enable_nat_instance      = var.enable_nat_instance
  enable_nat_gateway       = var.enable_nat_gateway
  ami_id                   = var.ami_id
  tags                     = local.common_tags
}

# 2. S3 Storage Module (App Storage Bucket & ALB Access Logs Bucket)
module "s3" {
  source = "./modules/s3"

  name_prefix = var.name_prefix
  aws_region  = var.aws_region
  tags        = local.common_tags
}

# 3. Security Module (Least-Privilege Security Groups & IAM Instance Profile)
module "security" {
  source = "./modules/security"

  name_prefix       = var.name_prefix
  vpc_id            = module.vpc.vpc_id
  app_port          = 80
  db_port           = 3306
  s3_app_bucket_arn = module.s3.app_bucket_arn
  aws_region        = var.aws_region
  tags              = local.common_tags
}

# 4. Database Module (RDS MySQL in Private Subnets & AWS Secrets Manager)
module "rds" {
  source = "./modules/rds"

  name_prefix           = var.name_prefix
  private_db_subnet_ids = module.vpc.private_db_subnet_ids
  rds_security_group_id = module.security.rds_security_group_id
  db_instance_class     = var.db_instance_class
  db_name               = var.db_name
  db_username           = var.db_username
  tags                  = local.common_tags
}

# 5. Application Load Balancer Module (ALB, Target Group, HTTPS with ACM Certificate, Access Logging)
module "alb" {
  source = "./modules/alb"

  name_prefix            = var.name_prefix
  vpc_id                 = module.vpc.vpc_id
  public_subnet_ids      = module.vpc.public_subnet_ids
  alb_security_group_id  = module.security.alb_security_group_id
  app_port               = 80
  alb_logs_bucket_name   = module.s3.alb_logs_bucket_name
  dummy_domain_name      = var.dummy_domain_name
  redirect_http_to_https = var.redirect_http_to_https
  tags                   = local.common_tags
}

# 6. Auto Scaling Module (EC2 Launch Template, Auto Scaling Group in Private App Subnets)
module "asg" {
  source = "./modules/asg"

  name_prefix            = var.name_prefix
  private_app_subnet_ids = module.vpc.private_app_subnet_ids
  app_security_group_id  = module.security.app_security_group_id
  instance_profile_name  = module.security.instance_profile_name
  target_group_arn       = module.alb.target_group_arn
  instance_type          = var.instance_type
  ami_id                 = var.ami_id
  min_size               = var.asg_min_size
  max_size               = var.asg_max_size
  desired_capacity       = var.asg_desired_capacity
  s3_bucket_name         = module.s3.app_bucket_name
  secret_name            = module.rds.secret_name
  aws_region             = var.aws_region
  tags                   = local.common_tags
}
