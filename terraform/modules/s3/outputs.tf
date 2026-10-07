output "app_bucket_name" {
  description = "Name of the S3 Application storage bucket"
  value       = aws_s3_bucket.app_storage.id
}

output "app_bucket_arn" {
  description = "ARN of the S3 Application storage bucket"
  value       = aws_s3_bucket.app_storage.arn
}

output "alb_logs_bucket_name" {
  description = "Name of the ALB Access Logs S3 bucket"
  value       = aws_s3_bucket.alb_logs.id
}

output "alb_logs_bucket_arn" {
  description = "ARN of the ALB Access Logs S3 bucket"
  value       = aws_s3_bucket.alb_logs.arn
}
