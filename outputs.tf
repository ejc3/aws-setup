output "cluster_endpoint" {
  description = "Aurora cluster endpoint (write)"
  value       = aws_rds_cluster.aurora.endpoint
}

output "cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint (read-only)"
  value       = aws_rds_cluster.aurora.reader_endpoint
}

output "db_address" {
  description = "Database address (without port)"
  value       = aws_rds_cluster.aurora.endpoint
}

output "db_port" {
  description = "Database port"
  value       = aws_rds_cluster.aurora.port
}

output "db_name" {
  description = "Database name"
  value       = aws_rds_cluster.aurora.database_name
}

output "db_username" {
  description = "Database username"
  value       = aws_rds_cluster.aurora.master_username
  sensitive   = true
}

output "db_password" {
  description = "Database password (auto-generated)"
  value       = random_password.db_password.result
  sensitive   = true
}

output "connection_string" {
  description = "MySQL connection string"
  value       = "mysql -h ${aws_rds_cluster.aurora.endpoint} -P ${aws_rds_cluster.aurora.port} -u ${aws_rds_cluster.aurora.master_username} -p ${aws_rds_cluster.aurora.database_name}"
  sensitive   = true
}

output "iam_policy_arn" {
  description = "ARN of the IAM policy for RDS IAM authentication"
  value       = aws_iam_policy.rds_connect.arn
}

output "iam_connect_instructions" {
  description = "Instructions for IAM authentication setup"
  value       = <<-EOT
    To use IAM authentication:
    1. Attach the policy to your IAM user/role:
       aws iam attach-user-policy --user-name YOUR_USER --policy-arn ${aws_iam_policy.rds_connect.arn}
       OR
       aws iam attach-role-policy --role-name YOUR_ROLE --policy-arn ${aws_iam_policy.rds_connect.arn}

    2. Create a database user for IAM auth (connect with password first):
       CREATE USER 'iamuser'@'%' IDENTIFIED WITH AWSAuthenticationPlugin AS 'RDS';
       GRANT ALL PRIVILEGES ON *.* TO 'iamuser'@'%';
       FLUSH PRIVILEGES;

    3. Connect using IAM token:
       make connect-iam
  EOT
}

output "auto_pause_config" {
  description = "Auto-pause configuration details"
  value = {
    min_capacity        = aws_rds_cluster.aurora.serverlessv2_scaling_configuration[0].min_capacity
    max_capacity        = aws_rds_cluster.aurora.serverlessv2_scaling_configuration[0].max_capacity
    auto_pause_enabled  = aws_rds_cluster.aurora.serverlessv2_scaling_configuration[0].min_capacity == 0
    seconds_until_pause = aws_rds_cluster.aurora.serverlessv2_scaling_configuration[0].min_capacity == 0 ? aws_rds_cluster.aurora.serverlessv2_scaling_configuration[0].seconds_until_auto_pause : null
    pause_delay_minutes = aws_rds_cluster.aurora.serverlessv2_scaling_configuration[0].min_capacity == 0 ? aws_rds_cluster.aurora.serverlessv2_scaling_configuration[0].seconds_until_auto_pause / 60 : null
  }
}

# Development Instance Outputs
output "dev_instance_id" {
  description = "Development instance ID"
  value       = var.enable_dev_instance ? aws_instance.dev[0].id : null
}

output "dev_instance_state" {
  description = "Development instance state"
  value       = var.enable_dev_instance ? aws_instance.dev[0].instance_state : null
}

output "dev_ssh_command" {
  description = "Command to SSH into dev instance via SSM"
  value       = var.enable_dev_instance ? "aws ssm start-session --target ${aws_instance.dev[0].id} --region ${var.aws_region}" : "Dev instance not enabled"
}

# ECR Outputs
output "ecr_repository_url" {
  description = "ECR repository URL for all demos"
  value       = aws_ecr_repository.demos.repository_url
}
