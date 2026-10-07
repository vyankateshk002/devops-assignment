output "alb_public_dns" {
  description = "Public DNS hostname of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

output "https_application_url" {
  description = "Working HTTPS Application URL (Terminates TLS with ACM Certificate)"
  value       = module.alb.https_url
}

output "http_application_url" {
  description = "Working HTTP Application URL (Direct access via ALB DNS name)"
  value       = module.alb.http_url
}

output "health_check_url" {
  description = "Application Health Check Endpoint"
  value       = "${module.alb.http_url}/health"
}

output "rds_endpoint" {
  description = "Private RDS MySQL endpoint (Not accessible from the public internet)"
  value       = module.rds.db_endpoint
}

output "secrets_manager_secret_name" {
  description = "AWS Secrets Manager Secret Name containing the database credentials"
  value       = module.rds.secret_name
  sensitive   = true
}

output "s3_app_storage_bucket" {
  description = "S3 Bucket for application media and data storage"
  value       = module.s3.app_bucket_name
}

output "s3_alb_access_logs_bucket" {
  description = "S3 Bucket storing ALB HTTP/HTTPS access logs"
  value       = module.s3.alb_logs_bucket_name
}

output "acm_certificate_arn" {
  description = "AWS Certificate Manager (ACM) SSL Certificate ARN"
  value       = module.alb.acm_certificate_arn
}

output "nat_strategy" {
  description = "Active NAT strategy used for private subnet egress"
  value       = var.enable_nat_instance && !var.enable_nat_gateway ? "100% Free-Tier EC2 NAT Instance (t2.micro - $0.00)" : "AWS Managed NAT Gateway (Paid)"
}
