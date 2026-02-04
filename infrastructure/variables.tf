# Configuração AWS
variable "aws_region" {
  description = "Região AWS para os recursos"
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Nome do projeto para nomenclatura dos recursos"
  type        = string
  default     = "financial-batch-processor"
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# Configuração S3
variable "s3_transactions_bucket_name" {
  description = "Nome do bucket S3 para dados de transações"
  type        = string
}

variable "s3_glue_scripts_bucket_name" {
  description = "Nome do bucket S3 para scripts do Glue"
  type        = string
}

# Configuração DynamoDB
variable "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB para dados de clientes"
  type        = string
  default     = "customer-registration"
}

variable "dynamodb_billing_mode" {
  description = "Modo de cobrança DynamoDB (PROVISIONED ou PAY_PER_REQUEST)"
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "dynamodb_read_capacity" {
  description = "Unidades de capacidade de leitura DynamoDB (apenas para modo PROVISIONED)"
  type        = number
  default     = 5
}

variable "dynamodb_write_capacity" {
  description = "Unidades de capacidade de escrita DynamoDB (apenas para modo PROVISIONED)"
  type        = number
  default     = 5
}

# Configuração OpenSearch
variable "opensearch_domain_name" {
  description = "Nome do domínio OpenSearch"
  type        = string
  default     = "financial-txns"
}

variable "opensearch_version" {
  description = "Versão do OpenSearch"
  type        = string
  default     = "OpenSearch_2.11"
}

variable "opensearch_instance_type" {
  description = "Tipo de instância OpenSearch"
  type        = string
  default     = "t3.small.search"
}

variable "opensearch_instance_count" {
  description = "Número de instâncias OpenSearch"
  type        = number
  default     = 1
}

variable "opensearch_ebs_volume_size" {
  description = "Tamanho do volume EBS em GB para OpenSearch"
  type        = number
  default     = 10
}

variable "opensearch_ebs_volume_type" {
  description = "Tipo de volume EBS para OpenSearch"
  type        = string
  default     = "gp3"
}

variable "opensearch_allowed_ips" {
  description = "Lista de endereços IP permitidos a acessar o OpenSearch"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Configuração do job Glue
variable "glue_job_name" {
  description = "Nome do job Glue"
  type        = string
  default     = "financial-transaction-processor"
}

variable "glue_version" {
  description = "Versão do Glue (4.0 ou 5.0)"
  type        = string
  default     = "4.0"
}

variable "glue_worker_type" {
  description = "Tipo de worker Glue (G.1X ou G.2X)"
  type        = string
  default     = "G.1X"
}

variable "glue_number_of_workers" {
  description = "Número de workers do Glue"
  type        = number
  default     = 2
}

variable "glue_max_retries" {
  description = "Número máximo de tentativas do job Glue"
  type        = number
  default     = 1
}

variable "glue_timeout_minutes" {
  description = "Timeout do job Glue em minutos"
  type        = number
  default     = 60
}

# Configuração VPC opcional
variable "vpc_id" {
  description = "ID da VPC para OpenSearch (opcional)"
  type        = string
  default     = ""
}

variable "private_subnet_ids" {
  description = "IDs das subnets privadas para OpenSearch (opcional)"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "IDs dos security groups para o job Glue (opcional)"
  type        = list(string)
  default     = []
}

# Tags
variable "tags" {
  description = "Tags a aplicar a todos os recursos"
  type        = map(string)
  default = {
    Project     = "FinancialBatchProcessor"
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}
