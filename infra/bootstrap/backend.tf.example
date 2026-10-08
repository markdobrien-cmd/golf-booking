# Step 2 of the bootstrap: rename this file to backend.tf, then run
#   terraform output -raw backend_config > backend.hcl
#   terraform init -migrate-state -backend-config=backend.hcl
# Terraform copies the local state into the S3 bucket it just created.
#
# The settings live in backend.hcl (not committed) because the bucket name contains your AWS account ID.
terraform {
  backend "s3" {}
}
