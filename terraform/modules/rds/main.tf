# Generate a secure random password for MySQL
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# 1. DB Subnet Group across private subnets in 2 Availability Zones
resource "aws_db_subnet_group" "this" {
  name        = "${var.name_prefix}-db-subnet-group"
  description = "Subnet group for RDS MySQL in private DB subnets"
  subnet_ids  = var.private_db_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-db-subnet-group"
  })
}

# 2. RDS MySQL Instance (100% Free Tier Eligible: db.t3.micro, 20GB, Single-AZ)
resource "aws_db_instance" "this" {
  identifier        = "${var.name_prefix}-mysql"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_type      = "gp3"

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.rds_security_group_id]

  multi_az            = false # Single-AZ for Free Tier compliance
  publicly_accessible = false # Strict private isolation
  storage_encrypted   = true  # AWS best practice encryption at rest

  skip_final_snapshot     = true  # Allows clean deletion without snapshot costs
  deletion_protection     = false # Facilitates testing and clean teardown
  backup_retention_period = 0     # Disable automated backups to eliminate storage charges

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-mysql"
  })
}

# 3. AWS Secrets Manager Secret for secure DB credential storage
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.name_prefix}-db-secret-${random_password.db_password.result != "" ? "mysql" : "creds"}"
  description             = "Master credentials for RDS MySQL database"
  recovery_window_in_days = 0 # Immediate deletion on destroy

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-db-credentials"
  })
}

# Store JSON credentials in Secrets Manager
resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    engine   = "mysql"
    host     = aws_db_instance.this.address
    port     = aws_db_instance.this.port
    username = var.db_username
    password = random_password.db_password.result
    dbname   = var.db_name
  })
}
