resource "scaleway_object_bucket_policy" "bucket_access" {
  for_each = var.bucket_names

  bucket = each.value
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid       = "IamPolicyBucketAccess"
        Effect    = "Allow"
        Principal = { SCW = "application_id:${scaleway_iam_application.application.id}" }
        Action    = var.bucket_actions
        Resource  = [each.value, "${each.value}/*"]
      }
      ], var.admin_project_id != null ? [
      {
        Sid       = "IamPolicyBucketAccessAdmin"
        Effect    = "Allow"
        Principal = { SCW = "project_id:${var.admin_project_id}" }
        Action    = ["s3:*"]
        Resource  = [each.value, "${each.value}/*"]
      }
    ] : [])
  })
}
