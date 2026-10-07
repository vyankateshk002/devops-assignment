output "alb_security_group_id" {
  description = "Security Group ID of the ALB"
  value       = aws_security_group.alb.id
}

output "app_security_group_id" {
  description = "Security Group ID of the EC2 App instances"
  value       = aws_security_group.app.id
}

output "rds_security_group_id" {
  description = "Security Group ID of the RDS MySQL database"
  value       = aws_security_group.rds.id
}

output "instance_profile_name" {
  description = "Name of the IAM Instance Profile"
  value       = aws_iam_instance_profile.this.name
}

output "instance_profile_arn" {
  description = "ARN of the IAM Instance Profile"
  value       = aws_iam_instance_profile.this.arn
}

output "iam_role_name" {
  description = "Name of the EC2 IAM Role"
  value       = aws_iam_role.ec2.name
}
