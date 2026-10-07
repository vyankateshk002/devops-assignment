variable "name_prefix" {
  type        = string
  description = "Prefix for all resource names"
  default     = "devops-assignment"
}

variable "private_app_subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for EC2 instances (Private App Subnets)"
}

variable "app_security_group_id" {
  type        = string
  description = "Security Group ID for the application instances"
}

variable "instance_profile_name" {
  type        = string
  description = "Name of the IAM Instance Profile"
}

variable "target_group_arn" {
  type        = string
  description = "ARN of the ALB Target Group to register instances with"
}

variable "instance_type" {
  type        = string
  description = "EC2 Instance type (Free Tier: t2.micro or t3.micro)"
  default     = "t2.micro"
}

variable "min_size" {
  type        = number
  description = "Minimum number of instances in the ASG"
  default     = 1
}

variable "max_size" {
  type        = number
  description = "Maximum number of instances in the ASG"
  default     = 2
}

variable "desired_capacity" {
  type        = number
  description = "Desired number of instances in the ASG"
  default     = 1
}

variable "s3_bucket_name" {
  type        = string
  description = "Name of the S3 application storage bucket"
}

variable "secret_name" {
  type        = string
  description = "Name of the AWS Secrets Manager secret for DB credentials"
}

variable "aws_region" {
  type        = string
  description = "AWS Region"
  default     = "us-east-1"
}

variable "tags" {
  type        = map(string)
  description = "Common tags"
  default     = {}
}
