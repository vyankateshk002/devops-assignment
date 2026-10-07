variable "aws_region" {
  type        = string
  description = "AWS region for deployment"
  default     = "us-east-1"
}

variable "aws_profile" {
  type        = string
  description = "AWS CLI profile name configured for the assignment (non-default)"
  default     = "assignment-access-key"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
  default     = "dev"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for all resource names"
  default     = "devops-assignment"
}

variable "dummy_domain_name" {
  type        = string
  description = "Dummy domain name for the ACM SSL certificate"
  default     = "app.devops-assignment.internal"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones for multi-AZ high availability"
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public subnet CIDRs (ALB & NAT)"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  type        = list(string)
  description = "Private application subnet CIDRs (EC2 ASG)"
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "private_db_subnet_cidrs" {
  type        = list(string)
  description = "Private database subnet CIDRs (RDS MySQL)"
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

variable "ami_id" {
  type        = string
  description = "Optional explicit AMI ID for EC2 instances. If empty, latest Amazon Linux 2023 AMI is resolved automatically."
  default     = ""
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type (Free Tier: t2.micro or t3.micro)"
  default     = "t2.micro"
}

variable "asg_min_size" {
  type        = number
  description = "Minimum size of Auto Scaling Group"
  default     = 1
}

variable "asg_max_size" {
  type        = number
  description = "Maximum size of Auto Scaling Group"
  default     = 2
}

variable "asg_desired_capacity" {
  type        = number
  description = "Desired capacity of Auto Scaling Group"
  default     = 1
}

variable "db_instance_class" {
  type        = string
  description = "RDS MySQL instance class (Free Tier: db.t3.micro or db.t2.micro)"
  default     = "db.t3.micro"
}

variable "db_name" {
  type        = string
  description = "MySQL database name"
  default     = "devops_db"
}

variable "db_username" {
  type        = string
  description = "MySQL master username"
  default     = "admin"
}

variable "enable_nat_instance" {
  type        = bool
  description = "Use 100% Free-Tier t2.micro NAT instance ($0.00 cost) instead of AWS Managed NAT Gateway ($32.40/month)"
  default     = true
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Set to true only if you want an AWS Managed NAT Gateway (Paid resource)"
  default     = false
}

variable "redirect_http_to_https" {
  type        = bool
  description = "Whether to redirect port 80 to 443. Set to false to allow testing both HTTP and HTTPS directly via ALB DNS without browser cert warnings blocking HTTP."
  default     = false
}
