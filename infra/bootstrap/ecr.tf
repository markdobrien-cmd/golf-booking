resource "aws_ecr_repository" "service" {
  for_each = var.services

  name = "${var.project}/${each.key}"

  # Tags are git SHAs and can never be overwritten, so a tag always means the same image.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Keep the 20 newest images per service; storage is cheap but not free.
resource "aws_ecr_lifecycle_policy" "service" {
  for_each   = aws_ecr_repository.service
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 20 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}
