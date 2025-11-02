# Application Load Balancer for buckman proxy instances
# Provides high availability and health checks for 2 instances

# Security group for ALB
resource "aws_security_group" "alb" {
  count       = var.enable_dev_instance ? 1 : 0
  name_prefix = "${var.project_name}-alb-sg-"
  description = "Security group for Application Load Balancer"
  vpc_id      = local.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from internet"
  }

  # HTTPS access from anywhere (for future use)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from internet"
  }

  # All outbound traffic to instances
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  count              = var.enable_dev_instance ? 1 : 0
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[0].id]
  subnets            = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id]

  enable_deletion_protection = false
  enable_http2               = true

  tags = {
    Name        = "${var.project_name}-alb"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# Target group for proxy instances (port 8080)
resource "aws_lb_target_group" "proxy" {
  count    = var.enable_dev_instance ? 1 : 0
  name     = "${var.project_name}-proxy-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = local.vpc_id

  # Health check on proxy endpoint
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 10
    path                = "/health"
    port                = 8080
    protocol            = "HTTP"
    matcher             = "200"
  }

  # Deregistration delay for graceful shutdown
  deregistration_delay = 10

  tags = {
    Name = "${var.project_name}-proxy-tg"
  }
}

# HTTP Listener - forward to proxy instances on port 8080
resource "aws_lb_listener" "http" {
  count             = var.enable_dev_instance ? 1 : 0
  load_balancer_arn = aws_lb.main[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.proxy[0].arn
  }
}

# Target group attachment for instances (done in dev-instance.tf)
