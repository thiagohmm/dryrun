# Outputs S3
output "s3_transactions_bucket" {
  description = "Nome do bucket S3 para dados de transações"
  value       = aws_s3_bucket.transactions.id
}

output "s3_transactions_bucket_arn" {
  description = "ARN do bucket S3 para dados de transações"
  value       = aws_s3_bucket.transactions.arn
}

output "glue_scripts_bucket" {
  description = "Nome do bucket S3 para scripts do Glue"
  value       = aws_s3_bucket.glue_scripts.id
}

output "glue_scripts_bucket_arn" {
  description = "ARN do bucket S3 para scripts do Glue"
  value       = aws_s3_bucket.glue_scripts.arn
}

# Outputs DynamoDB
output "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB para dados de clientes"
  value       = aws_dynamodb_table.customer_registration.name
}

output "dynamodb_table_arn" {
  description = "ARN da tabela DynamoDB"
  value       = aws_dynamodb_table.customer_registration.arn
}

# Outputs OpenSearch
output "opensearch_domain_name" {
  description = "Nome do domínio OpenSearch"
  value       = aws_opensearch_domain.financial_transactions.domain_name
}

output "opensearch_endpoint" {
  description = "Endpoint do domínio OpenSearch"
  value       = aws_opensearch_domain.financial_transactions.endpoint
}

output "opensearch_domain_id" {
  description = "ID do domínio OpenSearch"
  value       = aws_opensearch_domain.financial_transactions.domain_id
}

output "opensearch_arn" {
  description = "ARN do domínio OpenSearch"
  value       = aws_opensearch_domain.financial_transactions.arn
}

output "opensearch_kibana_endpoint" {
  description = "Endpoint do OpenSearch Dashboards"
  value       = aws_opensearch_domain.financial_transactions.dashboard_endpoint
}

output "opensearch_master_user" {
  description = "Nome de usuário mestre do OpenSearch"
  value       = var.opensearch_master_user
  sensitive   = true
}

output "opensearch_master_password" {
  description = "Senha do usuário mestre do OpenSearch"
  value       = var.opensearch_master_password
  sensitive   = true
}

# Outputs Glue
output "glue_job_name" {
  description = "Nome do job Glue"
  value       = aws_glue_job.financial_transaction_processor.name
}

output "glue_job_arn" {
  description = "ARN do job Glue"
  value       = aws_glue_job.financial_transaction_processor.arn
}

output "glue_role_arn" {
  description = "ARN do papel IAM do job Glue"
  value       = aws_iam_role.glue_job.arn
}

output "glue_catalog_database" {
  description = "Nome do banco de dados do catálogo Glue"
  value       = aws_glue_catalog_database.financial_data.name
}

# Outputs gerais
output "aws_region" {
  description = "Região AWS"
  value       = local.region
}

output "account_id" {
  description = "ID da conta AWS"
  value       = local.account_id
}

# Comandos de início rápido
output "quick_start_commands" {
  description = "Comandos de início rápido para usar a infraestrutura"
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

# Strings de conexão para scripts de geração de dados
output "data_generation_config" {
  description = "Configuração para scripts de geração de dados"
  value = {
    aws_region          = local.region
    s3_bucket           = aws_s3_bucket.transactions.id
    dynamodb_table      = aws_dynamodb_table.customer_registration.name
    opensearch_endpoint = aws_opensearch_domain.financial_transactions.endpoint
  }
}
