variable "name_prefix" {
  type        = string
  description = "Prefix for all resource names"
  default     = "devops-assignment"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = list(string)
  description = "List of Availability Zones to deploy subnets into"
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets (ALB & NAT)"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private application subnets (EC2 ASG)"
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "private_db_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private database subnets (RDS MySQL)"
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

variable "enable_nat_instance" {
  type        = bool
  description = "Use 100% Free-Tier t2.micro NAT instance instead of AWS Managed NAT Gateway ($32/mo)"
  default     = true
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Set to true only if you explicitly want AWS Managed NAT Gateway (Paid resource)"
  default     = false
}

variable "nat_instance_type" {
  type        = string
  description = "EC2 instance type for the Free-Tier NAT instance"
  default     = "t2.micro"
}

variable "tags" {
  type        = map(string)
  description = "Common tags"
  default     = {}
}
