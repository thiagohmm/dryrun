# S3 Outputs
output "s3_transactions_bucket" {
  description = "S3 bucket name for transaction data"
  value       = aws_s3_bucket.transactions.id
}

output "s3_transactions_bucket_arn" {
  description = "S3 bucket ARN for transaction data"
  value       = aws_s3_bucket.transactions.arn
}

output "glue_scripts_bucket" {
  description = "S3 bucket name for Glue scripts"
  value       = aws_s3_bucket.glue_scripts.id
}

output "glue_scripts_bucket_arn" {
  description = "S3 bucket ARN for Glue scripts"
  value       = aws_s3_bucket.glue_scripts.arn
}

# DynamoDB Outputs
output "dynamodb_table_name" {
  description = "DynamoDB table name for customer data"
  value       = aws_dynamodb_table.customer_registration.name
}

output "dynamodb_table_arn" {
  description = "DynamoDB table ARN"
  value       = aws_dynamodb_table.customer_registration.arn
}

# OpenSearch Outputs
output "opensearch_domain_name" {
  description = "OpenSearch domain name"
  value       = aws_opensearch_domain.financial_transactions.domain_name
}

output "opensearch_endpoint" {
  description = "OpenSearch domain endpoint"
  value       = aws_opensearch_domain.financial_transactions.endpoint
}

output "opensearch_domain_id" {
  description = "OpenSearch domain ID"
  value       = aws_opensearch_domain.financial_transactions.domain_id
}

output "opensearch_arn" {
  description = "OpenSearch domain ARN"
  value       = aws_opensearch_domain.financial_transactions.arn
}

output "opensearch_kibana_endpoint" {
  description = "OpenSearch Dashboards endpoint"
  value       = aws_opensearch_domain.financial_transactions.dashboard_endpoint
}

# Glue Outputs
output "glue_job_name" {
  description = "Glue job name"
  value       = aws_glue_job.financial_transaction_processor.name
}

output "glue_job_arn" {
  description = "Glue job ARN"
  value       = aws_glue_job.financial_transaction_processor.arn
}

output "glue_role_arn" {
  description = "Glue job IAM role ARN"
  value       = aws_iam_role.glue_job.arn
}

output "glue_catalog_database" {
  description = "Glue catalog database name"
  value       = aws_glue_catalog_database.financial_data.name
}

# General Outputs
output "aws_region" {
  description = "AWS region"
  value       = local.region
}

output "account_id" {
  description = "AWS account ID"
  value       = local.account_id
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Quick start commands for using the infrastructure"
  value       = <<-EOT
    # Upload Glue Job JAR
    aws s3 cp glue-job/target/scala-2.12/financial-transaction-processor_2.12-1.0.jar s3://${aws_s3_bucket.glue_scripts.id}/scripts/

    # Run Glue Job
    aws glue start-job-run --job-name ${aws_glue_job.financial_transaction_processor.name} \
      --arguments='--year=2024,--month=01,--day=15'

    # Query OpenSearch
    curl -X GET "https://${aws_opensearch_domain.financial_transactions.endpoint}/financial-transactions/_search?pretty"

    # Check DynamoDB
    aws dynamodb scan --table-name ${aws_dynamodb_table.customer_registration.name} --max-items 5

    # List S3 transactions
    aws s3 ls s3://${aws_s3_bucket.transactions.id}/transactions/ --recursive
  EOT
}

# Connection strings for data generation scripts
output "data_generation_config" {
  description = "Configuration for data generation scripts"
  value = {
    aws_region          = local.region
    s3_bucket           = aws_s3_bucket.transactions.id
    dynamodb_table      = aws_dynamodb_table.customer_registration.name
    opensearch_endpoint = aws_opensearch_domain.financial_transactions.endpoint
  }
}
