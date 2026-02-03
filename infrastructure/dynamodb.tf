# Tabela DynamoDB para dados de cadastro de clientes
resource "aws_dynamodb_table" "customer_registration" {
  name         = var.dynamodb_table_name
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "numero_unico_conta"

  # Define capacidade apenas se usar modo PROVISIONED
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  attribute {
    name = "numero_unico_conta"
    type = "S"
  }

  # Habilita recuperação point-in-time para proteção de dados
  point_in_time_recovery {
    enabled = true
  }

  # Habilita criptografia em repouso
  server_side_encryption {
    enabled = true
  }

  # Habilita TTL (opcional - pode ser usado para retenção de dados)
  ttl {
    enabled        = false
    attribute_name = "ttl"
  }

  tags = merge(
    local.common_tags,
    {
      Name    = "${var.project_name}-customer-registration-${var.environment}"
      Purpose = "Armazenar dados de cadastro de clientes para enriquecimento"
    }
  )
}

# Alarmes CloudWatch para DynamoDB (opcional mas recomendado)
resource "aws_cloudwatch_metric_alarm" "dynamodb_read_throttle" {
  alarm_name          = "${var.dynamodb_table_name}-read-throttle"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReadThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors DynamoDB read throttle events"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = aws_dynamodb_table.customer_registration.name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_write_throttle" {
  alarm_name          = "${var.dynamodb_table_name}-write-throttle"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "WriteThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors DynamoDB write throttle events"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = aws_dynamodb_table.customer_registration.name
  }

  tags = local.common_tags
}
