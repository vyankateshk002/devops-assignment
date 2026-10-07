variable "name_prefix" {
  type        = string
  description = "Prefix for all resource names"
  default     = "devops-assignment"
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
