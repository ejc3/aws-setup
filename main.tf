terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.13"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC Configuration - Use existing or create new
data "aws_vpcs" "existing" {
  filter {
    name   = "tag:Name"
    values = ["${var.project_name}-vpc"]
  }
}

resource "aws_vpc" "main" {
  count                = length(data.aws_vpcs.existing.ids) > 0 ? 0 : 1
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

data "aws_vpc" "selected" {
  id = length(data.aws_vpcs.existing.ids) > 0 ? tolist(data.aws_vpcs.existing.ids)[0] : aws_vpc.main[0].id
}

locals {
  vpc_id = data.aws_vpc.selected.id
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = local.vpc_id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Route Table for public subnets
resource "aws_route_table" "public" {
  vpc_id = local.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Associate route table with subnet A
resource "aws_route_table_association" "subnet_a" {
  subnet_id      = aws_subnet.subnet_a.id
  route_table_id = aws_route_table.public.id
}

# Associate route table with subnet B
resource "aws_route_table_association" "subnet_b" {
  subnet_id      = aws_subnet.subnet_b.id
  route_table_id = aws_route_table.public.id
}

# Subnets (need at least 2 for RDS)
resource "aws_subnet" "subnet_a" {
  vpc_id            = local.vpc_id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.project_name}-subnet-a"
  }
}

resource "aws_subnet" "subnet_b" {
  vpc_id            = local.vpc_id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${var.project_name}-subnet-b"
  }
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id]

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# Security Group for RDS
resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-rds-sg-"
  description = "Security group for RDS MySQL instance"
  vpc_id      = local.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  # Allow MySQL from anywhere (adjust for production!)
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "MySQL access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

# Generate random password for initial cluster creation
resource "random_password" "db_password" {
  length           = 20
  special          = true
  override_special = "_#%&-+=?!" # Avoid characters RDS forbids: '/', '@', '"', ' '
}

# IAM policy for RDS connect
data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "rds_connect" {
  name        = "${var.project_name}-rds-connect"
  description = "Allow IAM authentication to RDS"

  depends_on = [aws_rds_cluster_instance.aurora_serverless]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds-db:connect"
        ]
        Resource = "arn:aws:rds-db:${var.aws_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster_instance.aurora_serverless.dbi_resource_id}/iamuser"
      }
    ]
  })
}

# Aurora Serverless v2 MySQL Cluster
resource "aws_rds_cluster" "aurora" {
  cluster_identifier = var.db_identifier
  engine             = "aurora-mysql"
  engine_mode        = "provisioned" # Required for Serverless v2
  engine_version     = var.aurora_version
  database_name      = var.db_name
  master_username    = var.db_username
  master_password    = random_password.db_password.result

  # Enable IAM database authentication
  iam_database_authentication_enabled = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "mon:04:00-mon:05:00"

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.db_identifier}-final-snapshot"

  deletion_protection = var.deletion_protection
  storage_encrypted   = true

  # Serverless v2 scaling configuration with automatic pause
  serverlessv2_scaling_configuration {
    max_capacity             = var.serverless_max_capacity
    min_capacity             = var.serverless_min_capacity
    seconds_until_auto_pause = var.serverless_min_capacity == 0 ? var.seconds_until_auto_pause : null
  }

  tags = {
    Name = "${var.project_name}-aurora-serverless-cluster"
  }
}

# Aurora Serverless v2 Instance
resource "aws_rds_cluster_instance" "aurora_serverless" {
  identifier         = "${var.db_identifier}-instance"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version

  publicly_accessible = var.publicly_accessible

  tags = {
    Name = "${var.project_name}-aurora-serverless-instance"
  }
}

# Create IAM database user automatically
resource "null_resource" "create_iam_user" {
  depends_on = [aws_rds_cluster.aurora, aws_rds_cluster_instance.aurora_serverless]

  triggers = {
    cluster_id  = aws_rds_cluster.aurora.id
    instance_id = aws_rds_cluster_instance.aurora_serverless.id
  }

  provisioner "local-exec" {
    command = <<-EOC
      # Wait for database to be available
      sleep 30

      # Create IAM user
      MYSQL_PWD='${random_password.db_password.result}' mysql \
        --connect-timeout=60 \
        -h ${aws_rds_cluster.aurora.endpoint} \
        -u ${aws_rds_cluster.aurora.master_username} \
        ${aws_rds_cluster.aurora.database_name} <<SQL
      CREATE USER IF NOT EXISTS 'iamuser'@'%' IDENTIFIED WITH AWSAuthenticationPlugin AS 'RDS';
      GRANT SELECT, INSERT, UPDATE, DELETE ON *.* TO 'iamuser'@'%';
      FLUSH PRIVILEGES;
      SELECT 'IAM user created successfully' as status;
SQL
    EOC
  }
}
