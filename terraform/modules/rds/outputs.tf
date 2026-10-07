output "db_instance_id" {
  description = "RDS DB instance ID"
  value       = aws_db_instance.this.id
}

output "db_endpoint" {
  description = "Connection endpoint of the MySQL database"
  value       = aws_db_instance.this.endpoint
}

output "db_address" {
  description = "Hostname/address of the MySQL database"
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "Port of the MySQL database"
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.this.db_name
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "secret_name" {
  description = "Name of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.db_credentials.name
}
