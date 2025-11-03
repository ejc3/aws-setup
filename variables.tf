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
  description = "Minimum Aurora Serverless v2 capacity units (0 - 128). Set to 0 to enable automatic pause."
  type        = number
  default     = 0 # Automatic pause when idle
}

variable "serverless_max_capacity" {
  description = "Maximum Aurora Serverless v2 capacity units (0.5 - 128)"
  type        = number
  default     = 1 # Low max for dev environment
}

variable "seconds_until_auto_pause" {
  description = "Seconds of inactivity before automatic pause (300-86400). Only applies when min_capacity = 0."
  type        = number
  default     = 300 # 5 minutes - pause quickly for cost savings
}

variable "publicly_accessible" {
  description = "Whether the database is publicly accessible"
  type        = bool
  default     = true # Set to false for production
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the database"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Allow from anywhere - restrict for production!
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying"
  type        = bool
  default     = true # Set to false for production
}

variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = false # Set to true for production
}

variable "enable_account_tags" {
  description = "Enable account-level tagging (requires AWS Organizations)"
  type        = bool
  default     = false
}

# Development Instance Variables
variable "enable_dev_instance" {
  description = "Enable EC2 development instance"
  type        = bool
  default     = true
}

variable "dev_instance_type" {
  description = "EC2 instance type for dev instance"
  type        = string
  default     = "t3.medium"
}

variable "dev_volume_size" {
  description = "Size of persistent EBS volume in GB"
  type        = number
  default     = 100
}
