# AWS Configuration
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "financial-batch-processor"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# S3 Configuration
variable "s3_transactions_bucket_name" {
  description = "S3 bucket name for transaction data"
  type        = string
}

variable "s3_glue_scripts_bucket_name" {
  description = "S3 bucket name for Glue scripts"
  type        = string
}

# DynamoDB Configuration
variable "dynamodb_table_name" {
  description = "DynamoDB table name for customer data"
  type        = string
  default     = "customer-registration"
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PROVISIONED or PAY_PER_REQUEST)"
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "dynamodb_read_capacity" {
  description = "DynamoDB read capacity units (only for PROVISIONED mode)"
  type        = number
  default     = 5
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB write capacity units (only for PROVISIONED mode)"
  type        = number
  default     = 5
}

# OpenSearch Configuration
variable "opensearch_domain_name" {
  description = "OpenSearch domain name"
  type        = string
  default     = "financial-txns"
}

variable "opensearch_version" {
  description = "OpenSearch version"
  type        = string
  default     = "OpenSearch_2.11"
}

variable "opensearch_instance_type" {
  description = "OpenSearch instance type"
  type        = string
  default     = "t3.small.search"
}

variable "opensearch_instance_count" {
  description = "Number of OpenSearch instances"
  type        = number
  default     = 1
}

variable "opensearch_ebs_volume_size" {
  description = "EBS volume size in GB for OpenSearch"
  type        = number
  default     = 10
}

variable "opensearch_ebs_volume_type" {
  description = "EBS volume type for OpenSearch"
  type        = string
  default     = "gp3"
}

variable "opensearch_allowed_ips" {
  description = "List of IP addresses allowed to access OpenSearch"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Glue Job Configuration
variable "glue_job_name" {
  description = "Glue job name"
  type        = string
  default     = "financial-transaction-processor"
}

variable "glue_version" {
  description = "Glue version (4.0 or 5.0)"
  type        = string
  default     = "4.0"
}

variable "glue_worker_type" {
  description = "Glue worker type (G.1X or G.2X)"
  type        = string
  default     = "G.1X"
}

variable "glue_number_of_workers" {
  description = "Number of Glue workers"
  type        = number
  default     = 2
}

variable "glue_max_retries" {
  description = "Maximum number of retries for Glue job"
  type        = number
  default     = 1
}

variable "glue_timeout_minutes" {
  description = "Glue job timeout in minutes"
  type        = number
  default     = 60
}

# Optional VPC Configuration
variable "vpc_id" {
  description = "VPC ID for OpenSearch (optional)"
  type        = string
  default     = ""
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for OpenSearch (optional)"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Security group IDs for Glue job (optional)"
  type        = list(string)
  default     = []
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "FinancialBatchProcessor"
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}
