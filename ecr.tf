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
