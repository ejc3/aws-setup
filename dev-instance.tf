# Development Instance - Simple On-Demand with Stop/Start
# Cost: ~$8/month - zero complexity, everything persists

# Latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  count       = var.enable_dev_instance ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security group for dev instance
resource "aws_security_group" "dev" {
  count       = var.enable_dev_instance ? 1 : 0
  name_prefix = "${var.project_name}-dev-sg-"
  description = "Security group for development instance"
  vpc_id      = local.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  # No inbound rules - using SSM for access
  # All outbound traffic allowed for package installation, git, etc.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-dev-sg"
  }
}

# IAM role for dev instance (SSM access)
resource "aws_iam_role" "dev_instance" {
  count = var.enable_dev_instance ? 1 : 0
  name  = "${var.project_name}-dev-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-dev-instance-role"
  }
}

# Attach AWS managed policy for SSM
resource "aws_iam_role_policy_attachment" "dev_ssm" {
  count      = var.enable_dev_instance ? 1 : 0
  role       = aws_iam_role.dev_instance[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Policy to read GitHub token from Secrets Manager and access ECR
resource "aws_iam_role_policy" "dev_secrets" {
  count = var.enable_dev_instance ? 1 : 0
  name  = "${var.project_name}-dev-secrets-policy"
  role  = aws_iam_role.dev_instance[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:github-deploy-token-*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:ListImages"
        ]
        Resource = "*"
      }
    ]
  })
}

# Instance profile
resource "aws_iam_instance_profile" "dev" {
  count = var.enable_dev_instance ? 1 : 0
  name  = "${var.project_name}-dev-instance-profile"
  role  = aws_iam_role.dev_instance[0].name
}

# VPC Endpoints for SSM and S3 (private access, no public IP needed)
# S3 endpoint (Gateway type - free!) for package repos
resource "aws_vpc_endpoint" "s3" {
  count           = var.enable_dev_instance ? 1 : 0
  vpc_id          = local.vpc_id
  service_name    = "com.amazonaws.${var.aws_region}.s3"
  route_table_ids = [aws_route_table.public.id]

  tags = {
    Name = "${var.project_name}-s3-endpoint"
  }
}

# SSM endpoints (Interface type) for remote access
resource "aws_vpc_endpoint" "ssm" {
  count             = var.enable_dev_instance ? 1 : 0
  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type = "Interface"
  subnet_ids        = [aws_subnet.subnet_a.id]
  security_group_ids = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ssm-endpoint"
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  count             = var.enable_dev_instance ? 1 : 0
  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type = "Interface"
  subnet_ids        = [aws_subnet.subnet_a.id]
  security_group_ids = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ssmmessages-endpoint"
  }
}

resource "aws_vpc_endpoint" "ec2messages" {
  count             = var.enable_dev_instance ? 1 : 0
  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type = "Interface"
  subnet_ids        = [aws_subnet.subnet_a.id]
  security_group_ids = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ec2messages-endpoint"
  }
}

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  count       = var.enable_dev_instance ? 1 : 0
  name_prefix = "${var.project_name}-vpc-endpoints-sg-"
  description = "Security group for VPC endpoints"
  vpc_id      = local.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
    description = "HTTPS from VPC"
  }

  tags = {
    Name = "${var.project_name}-vpc-endpoints-sg"
  }
}

# Development instance (public IP for GitHub access)
resource "aws_instance" "dev" {
  count                       = var.enable_dev_instance ? 1 : 0
  ami                         = data.aws_ami.amazon_linux_2023[0].id
  instance_type               = var.dev_instance_type
  subnet_id                   = aws_subnet.subnet_a.id
  vpc_security_group_ids      = [aws_security_group.dev[0].id]
  iam_instance_profile        = aws_iam_instance_profile.dev[0].name
  associate_public_ip_address = true

  # Persistent root volume
  root_block_device {
    volume_size           = var.dev_volume_size
    volume_type           = "gp3"
    delete_on_termination = false # Volume persists when instance stops
    encrypted             = true

    tags = {
      Name = "${var.project_name}-dev-volume"
    }
  }

  # Bootstrap script
  user_data = file("${path.module}/user-data.sh")

  tags = {
    Name        = "${var.project_name}-dev-instance"
    Purpose     = "development"
    Environment = "dev"
    ManagedBy   = "terraform"
    AutoDeploy  = "true"
  }

  lifecycle {
    ignore_changes = [
      ami, # Don't force replacement on AMI updates
    ]
  }
}

# Upload container deployment script to instance
resource "null_resource" "upload_deploy_script" {
  count = var.enable_dev_instance ? 1 : 0

  depends_on = [aws_instance.dev]

  triggers = {
    instance_id = aws_instance.dev[0].id
    script_hash = filemd5("${path.module}/scripts/deploy-containers.sh")
  }

  provisioner "local-exec" {
    command = <<-EOC
      # Wait for SSM agent to be ready
      echo "Waiting for SSM agent to be ready..."
      for i in {1..30}; do
        if aws ssm describe-instance-information \
          --filters "Key=InstanceIds,Values=${aws_instance.dev[0].id}" \
          --region ${var.aws_region} \
          --query 'InstanceInformationList[0].PingStatus' \
          --output text 2>/dev/null | grep -q "Online"; then
          echo "SSM agent is online"
          break
        fi
        echo "Waiting for SSM agent... ($i/30)"
        sleep 10
      done

      # Upload script via SSM (base64 encode to avoid escaping issues)
      SCRIPT_B64=$(base64 -i ${path.module}/scripts/deploy-containers.sh)

      aws ssm send-command \
        --instance-ids ${aws_instance.dev[0].id} \
        --region ${var.aws_region} \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[\"echo '$SCRIPT_B64' | base64 -d > /home/ec2-user/deploy-containers.sh\",\"chmod +x /home/ec2-user/deploy-containers.sh\",\"chown ec2-user:ec2-user /home/ec2-user/deploy-containers.sh\"]" \
        --output text
    EOC
  }
}
