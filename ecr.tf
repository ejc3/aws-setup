# ECR Repository for containerized demos
# Single repository for all demos, using tags like nextjs-01-hello-world, python-01-talktui

resource "aws_ecr_repository" "demos" {
  name                 = "${var.project_name}/demos"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Name    = "${var.project_name}-demos"
    Purpose = "Container registry for all demos"
  }
}

# ECR lifecycle policy to keep only recent images (cost optimization)
# Keep last 100 images total - allows ~1-3 versions per demo even with 100 demos
resource "aws_ecr_lifecycle_policy" "demos" {
  repository = aws_ecr_repository.demos.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 100 images total"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 100
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# ECR Repository for buckman-runner (infrastructure deployment)
resource "aws_ecr_repository" "buckman_runner" {
  name                 = "${var.project_name}/buckman-runner"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Name    = "${var.project_name}-buckman-runner"
    Purpose = "Infrastructure deployment - runner service"
  }
}

# ECR Repository for buckman-version-server (infrastructure deployment)
resource "aws_ecr_repository" "buckman_version_server" {
  name                 = "${var.project_name}/buckman-version-server"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Name    = "${var.project_name}-buckman-version-server"
    Purpose = "Infrastructure deployment - version server"
  }
}

# ECR lifecycle policy for infrastructure images (keep last 10)
resource "aws_ecr_lifecycle_policy" "buckman_runner" {
  repository = aws_ecr_repository.buckman_runner.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "buckman_version_server" {
  repository = aws_ecr_repository.buckman_version_server.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}
