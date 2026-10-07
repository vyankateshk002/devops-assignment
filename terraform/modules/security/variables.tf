variable "name_prefix" {
  type        = string
  description = "Prefix for all resource names"
  default     = "devops-assignment"
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC"
}

variable "app_port" {
  type        = number
  description = "Port the application listens on"
  default     = 80
}

variable "db_port" {
  type        = number
  description = "Port the RDS MySQL listens on"
  default     = 3306
}

variable "s3_app_bucket_arn" {
  type        = string
  description = "ARN of the S3 application bucket"
  default     = "*"
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
