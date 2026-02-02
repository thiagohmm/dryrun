# S3 Bucket for Transaction Data
resource "aws_s3_bucket" "transactions" {
  bucket = var.s3_transactions_bucket_name

  tags = merge(
    local.common_tags,
    {
      Name    = "${var.project_name}-transactions-${var.environment}"
      Purpose = "Store financial transaction data"
    }
  )
}

# Enable versioning for transactions bucket
resource "aws_s3_bucket_versioning" "transactions" {
  bucket = aws_s3_bucket.transactions.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption for transactions bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "transactions" {
  bucket = aws_s3_bucket.transactions.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access for transactions bucket
resource "aws_s3_bucket_public_access_block" "transactions" {
  bucket = aws_s3_bucket.transactions.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket for Glue Scripts
resource "aws_s3_bucket" "glue_scripts" {
  bucket = var.s3_glue_scripts_bucket_name

  tags = merge(
    local.common_tags,
    {
      Name    = "${var.project_name}-glue-scripts-${var.environment}"
      Purpose = "Store Glue job scripts and JARs"
    }
  )
}

# Enable versioning for Glue scripts bucket
resource "aws_s3_bucket_versioning" "glue_scripts" {
  bucket = aws_s3_bucket.glue_scripts.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption for Glue scripts bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "glue_scripts" {
  bucket = aws_s3_bucket.glue_scripts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access for Glue scripts bucket
resource "aws_s3_bucket_public_access_block" "glue_scripts" {
  bucket = aws_s3_bucket.glue_scripts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy for transactions bucket (optional - archive old data)
resource "aws_s3_bucket_lifecycle_configuration" "transactions" {
  bucket = aws_s3_bucket.transactions.id

  rule {
    id     = "archive-old-transactions"
    status = "Enabled"

    filter {
      prefix = "transactions/"
    }

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 180
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}
