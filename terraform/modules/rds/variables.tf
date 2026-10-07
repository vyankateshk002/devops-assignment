variable "name_prefix" {
  type        = string
  description = "Prefix for all resource names"
  default     = "devops-assignment"
}

variable "private_db_subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for DB Subnet Group (Private subnets across 2 AZs)"
}

variable "rds_security_group_id" {
  type        = string
  description = "Security Group ID for RDS MySQL"
}

variable "db_instance_class" {
  type        = string
  description = "RDS MySQL instance class (Free Tier: db.t3.micro or db.t2.micro)"
  default     = "db.t3.micro"
}

variable "db_name" {
  type        = string
  description = "Name of the MySQL database"
  default     = "devops_db"
}

variable "db_username" {
  type        = string
  description = "Master username for MySQL"
  default     = "admin"
}

variable "tags" {
  type        = map(string)
  description = "Common tags"
  default     = {}
}
