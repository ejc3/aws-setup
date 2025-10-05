variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "aws-infrastructure"
}

variable "db_identifier" {
  description = "Database identifier"
  type        = string
  default     = "aurora-serverless-dev"
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "mydb"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "admin"
}

variable "aurora_version" {
  description = "Aurora MySQL engine version"
  type        = string
  default     = "8.0.mysql_aurora.3.10.1"
}

variable "serverless_min_capacity" {
  description = "Minimum Aurora Serverless v2 capacity units (0.5 - 128)."
  type        = number
  default     = 0.5  # Smallest value allowed for Serverless v2
}

variable "serverless_max_capacity" {
  description = "Maximum Aurora Serverless v2 capacity units (0.5 - 128)."
  type        = number
  default     = 1  # Low max for dev environment
}

variable "publicly_accessible" {
  description = "Whether the database is publicly accessible"
  type        = bool
  default     = true  # Set to false for production
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the database"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Allow from anywhere - restrict for production!
}

variable "backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying"
  type        = bool
  default     = true  # Set to false for production
}

variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = false  # Set to true for production
}
