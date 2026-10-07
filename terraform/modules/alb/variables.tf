variable "name_prefix" {
  type        = string
  description = "Prefix for all resource names"
  default     = "devops-assignment"
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs where ALB will be deployed"
}

variable "alb_security_group_id" {
  type        = string
  description = "Security Group ID for the ALB"
}

variable "app_port" {
  type        = number
  description = "Port the backend application listens on"
  default     = 80
}

variable "alb_logs_bucket_name" {
  type        = string
  description = "S3 bucket name for storing ALB access logs"
}

variable "dummy_domain_name" {
  type        = string
  description = "Dummy domain name for the ACM SSL certificate"
  default     = "app.devops-assignment.internal"
}

variable "redirect_http_to_https" {
  type        = bool
  description = "Whether to redirect HTTP (port 80) to HTTPS (port 443). False allows testing both HTTP and HTTPS directly via ALB DNS."
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Common tags"
  default     = {}
}
