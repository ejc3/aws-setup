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

# Production Instance Outputs
output "prod_instance_ids" {
  description = "Production instance IDs"
  value       = var.enable_dev_instance ? aws_instance.dev[*].id : []
}

output "prod_instance_states" {
  description = "Production instance states"
  value       = var.enable_dev_instance ? aws_instance.dev[*].instance_state : []
}

output "prod_ssh_commands" {
  description = "Commands to SSH into production instances via SSM"
  value       = var.enable_dev_instance ? [for inst in aws_instance.dev : "aws ssm start-session --target ${inst.id} --region ${var.aws_region}"] : []
}

# ALB Outputs
output "alb_dns_name" {
  description = "ALB DNS name for accessing the application"
  value       = var.enable_dev_instance ? aws_lb.main[0].dns_name : null
}

output "alb_url" {
  description = "Full ALB URL"
  value       = var.enable_dev_instance ? "http://${aws_lb.main[0].dns_name}" : null
}

output "alb_zone_id" {
  description = "ALB zone ID for Route53 records"
  value       = var.enable_dev_instance ? aws_lb.main[0].zone_id : null
}

# ECR Outputs
output "ecr_repository_url" {
  description = "ECR repository URL for all demos"
  value       = aws_ecr_repository.demos.repository_url
}

output "ecr_buckman_runner_url" {
  description = "ECR repository URL for buckman-runner"
  value       = aws_ecr_repository.buckman_runner.repository_url
}

output "ecr_buckman_version_server_url" {
  description = "ECR repository URL for buckman-version-server"
  value       = aws_ecr_repository.buckman_version_server.repository_url
}
