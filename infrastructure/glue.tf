# Papel IAM para o job Glue
resource "aws_iam_role" "glue_job" {
  name = "${var.project_name}-glue-job-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-glue-job-role"
    }
  )
}

# Anexa política gerenciada AWS do serviço Glue
resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_job.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Custom policy for S3 access
resource "aws_iam_role_policy" "glue_s3_access" {
  name = "${var.project_name}-glue-s3-access"
  role = aws_iam_role.glue_job.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.transactions.arn,
          "${aws_s3_bucket.transactions.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.glue_scripts.arn,
          "${aws_s3_bucket.glue_scripts.arn}/*"
        ]
      }
    ]
  })
}

# Política customizada para acesso ao DynamoDB
resource "aws_iam_role_policy" "glue_dynamodb_access" {
  name = "${var.project_name}-glue-dynamodb-access"
  role = aws_iam_role.glue_job.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:BatchGetItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:DescribeTable"
        ]
        Resource = [
          aws_dynamodb_table.customer_registration.arn,
          "${aws_dynamodb_table.customer_registration.arn}/*"
        ]
      }
    ]
  })
}

# Política customizada para acesso ao OpenSearch
resource "aws_iam_role_policy" "glue_opensearch_access" {
  name = "${var.project_name}-glue-opensearch-access"
  role = aws_iam_role.glue_job.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "es:ESHttpPost",
          "es:ESHttpPut",
          "es:ESHttpGet",
          "es:ESHttpHead",
          "es:DescribeElasticsearchDomain",
          "es:DescribeElasticsearchDomains"
        ]
        Resource = [
          aws_opensearch_domain.financial_transactions.arn,
          "${aws_opensearch_domain.financial_transactions.arn}/*"
        ]
      }
    ]
  })
}

# Política customizada para CloudWatch Logs
resource "aws_iam_role_policy" "glue_cloudwatch_logs" {
  name = "${var.project_name}-glue-cloudwatch-logs"
  role = aws_iam_role.glue_job.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws-glue/*"
        ]
      }
    ]
  })
}

# Grupo de log CloudWatch para o job Glue
resource "aws_cloudwatch_log_group" "glue_job" {
  name              = "/aws-glue/jobs/${var.glue_job_name}"
  retention_in_days = 7

  tags = local.common_tags
}

# Job Glue
resource "aws_glue_job" "financial_transaction_processor" {
  name              = var.glue_job_name
  role_arn          = aws_iam_role.glue_job.arn
  glue_version      = var.glue_version
  worker_type       = var.glue_worker_type
  number_of_workers = var.glue_number_of_workers
  max_retries       = var.glue_max_retries
  timeout           = var.glue_timeout_minutes

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/scripts/wrapper.scala"
  }

  default_arguments = {
    "--job-language"                     = "scala"
    "--class"                            = "FinancialTransactionProcessor"
    "--user-jars-first"                  = "true"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-continuous-log-filter"     = "true"
    "--enable-spark-ui"                  = "true"
    "--spark-event-logs-path"            = "s3://${aws_s3_bucket.glue_scripts.bucket}/spark-logs/"
    "--job-bookmark-option"              = "job-bookmark-disable"
    "--TempDir"                          = "s3://${aws_s3_bucket.glue_scripts.bucket}/temp/"
    "--extra-jars"                       = "s3://${aws_s3_bucket.glue_scripts.bucket}/scripts/financial-transaction-processor_2.12-1.0.jar"

    # Parâmetros específicos do job (podem ser sobrescritos em tempo de execução)
    "--s3_bucket"           = aws_s3_bucket.transactions.bucket
    "--dynamodb_table"      = aws_dynamodb_table.customer_registration.name
    "--opensearch_endpoint" = aws_opensearch_domain.financial_transactions.endpoint
    "--opensearch_index"    = "financial-transactions"
    "--aws_region"          = local.region
  }

  execution_property {
    max_concurrent_runs = 1
  }

  tags = merge(
    local.common_tags,
    {
      Name    = "${var.project_name}-glue-job"
      Purpose = "Processar e enriquecer transações financeiras"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.glue_service,
    aws_iam_role_policy.glue_s3_access,
    aws_iam_role_policy.glue_dynamodb_access,
    aws_iam_role_policy.glue_opensearch_access,
    aws_cloudwatch_log_group.glue_job
  ]
}

# Alarmes CloudWatch para o job Glue
resource "aws_cloudwatch_metric_alarm" "glue_job_failure" {
  alarm_name          = "${var.glue_job_name}-failure"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "glue.driver.aggregate.numFailedTasks"
  namespace           = "Glue"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Glue job has failed tasks"
  treat_missing_data  = "notBreaching"

  dimensions = {
    JobName = aws_glue_job.financial_transaction_processor.name
    Type    = "count"
  }

  tags = local.common_tags
}

# Banco de dados do catálogo Glue (opcional - para catálogo de dados)
resource "aws_glue_catalog_database" "financial_data" {
  name        = "${var.project_name}_${var.environment}"
  description = "Banco de dados do catálogo Glue para dados de transações financeiras"

  tags = local.common_tags
}

# Crawler Glue para dados no S3 (opcional - para descoberta automática de esquema)
resource "aws_glue_crawler" "transactions" {
  name          = "${var.project_name}-transactions-crawler"
  role          = aws_iam_role.glue_job.arn
  database_name = aws_glue_catalog_database.financial_data.name

  s3_target {
    path = "s3://${aws_s3_bucket.transactions.bucket}/transactions/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = {
        AddOrUpdateBehavior = "InheritFromTable"
      }
    }
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-transactions-crawler"
    }
  )
}
