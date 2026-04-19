resource "random_string" "bucket_suffix" {
  length = 6
  upper = false
  special = false
}

resource "aws_s3_bucket" "tf_state" {
  bucket = "${var.name_prefix}-tfstate-bucket-${random_string.bucket_suffix.result}"

  tags = {
    Name = "Terraform State"
  }
}

# Enable versioning
resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# DynamoDB for locking
resource "aws_dynamodb_table" "tf_lock" {
  name = "${var.name_prefix}-terraform-lock-table"
  hash_key = "LockID"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "LockID"
    type = "S"
  }
}