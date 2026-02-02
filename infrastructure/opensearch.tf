# OpenSearch Domain
resource "aws_opensearch_domain" "financial_transactions" {
  domain_name    = var.opensearch_domain_name
  engine_version = var.opensearch_version

  cluster_config {
    instance_type          = var.opensearch_instance_type
    instance_count         = var.opensearch_instance_count
    zone_awareness_enabled = var.opensearch_instance_count > 1

    dynamic "zone_awareness_config" {
      for_each = var.opensearch_instance_count > 1 ? [1] : []
      content {
        availability_zone_count = 2
      }
    }
  }

  ebs_options {
    ebs_enabled = true
    volume_size = var.opensearch_ebs_volume_size
    volume_type = var.opensearch_ebs_volume_type
    iops        = var.opensearch_ebs_volume_type == "gp3" ? 3000 : null
    throughput  = var.opensearch_ebs_volume_type == "gp3" ? 125 : null
  }

  # Encryption at rest
  encrypt_at_rest {
    enabled = true
  }

  # Node-to-node encryption
  node_to_node_encryption {
    enabled = true
  }

  # Domain endpoint options
  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  # Advanced security options (optional - can be enabled for production)
  advanced_security_options {
    enabled                        = false
    internal_user_database_enabled = false
  }

  # Advanced options
  advanced_options = {
    "rest.action.multi.allow_explicit_index" = "true"
    "override_main_response_version"         = "false"
  }

  # Access policy for public domain
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action   = "es:*"
        Resource = "arn:aws:es:${local.region}:${local.account_id}:domain/${var.opensearch_domain_name}/*"
        Condition = {
          IpAddress = {
            "aws:SourceIp" = var.opensearch_allowed_ips
          }
        }
      }
    ]
  })

  # Automated snapshots
  snapshot_options {
    automated_snapshot_start_hour = 23
  }

  # CloudWatch logging
  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch_application_logs.arn
    log_type                 = "ES_APPLICATION_LOGS"
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch_index_slow_logs.arn
    log_type                 = "INDEX_SLOW_LOGS"
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch_search_slow_logs.arn
    log_type                 = "SEARCH_SLOW_LOGS"
  }

  tags = merge(
    local.common_tags,
    {
      Name    = "${var.project_name}-opensearch-${var.environment}"
      Purpose = "Store enriched financial transactions"
    }
  )

  depends_on = [
    aws_cloudwatch_log_group.opensearch_application_logs,
    aws_cloudwatch_log_group.opensearch_index_slow_logs,
    aws_cloudwatch_log_group.opensearch_search_slow_logs,
    aws_cloudwatch_log_resource_policy.opensearch
  ]
}

# CloudWatch Log Groups for OpenSearch
resource "aws_cloudwatch_log_group" "opensearch_application_logs" {
  name              = "/aws/opensearch/${var.opensearch_domain_name}/application-logs"
  retention_in_days = 7

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "opensearch_index_slow_logs" {
  name              = "/aws/opensearch/${var.opensearch_domain_name}/index-slow-logs"
  retention_in_days = 7

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "opensearch_search_slow_logs" {
  name              = "/aws/opensearch/${var.opensearch_domain_name}/search-slow-logs"
  retention_in_days = 7

  tags = local.common_tags
}

# CloudWatch Log Resource Policy for OpenSearch
resource "aws_cloudwatch_log_resource_policy" "opensearch" {
  policy_name = "${var.opensearch_domain_name}-log-policy"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "es.amazonaws.com"
        }
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogStream"
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/opensearch/${var.opensearch_domain_name}/*"
      }
    ]
  })
}

# CloudWatch Alarms for OpenSearch
resource "aws_cloudwatch_metric_alarm" "opensearch_cluster_status_red" {
  alarm_name          = "${var.opensearch_domain_name}-cluster-status-red"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "ClusterStatus.red"
  namespace           = "AWS/ES"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "1"
  alarm_description   = "OpenSearch cluster status is red"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DomainName = aws_opensearch_domain.financial_transactions.domain_name
    ClientId   = local.account_id
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "opensearch_cluster_status_yellow" {
  alarm_name          = "${var.opensearch_domain_name}-cluster-status-yellow"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "ClusterStatus.yellow"
  namespace           = "AWS/ES"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "1"
  alarm_description   = "OpenSearch cluster status is yellow"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DomainName = aws_opensearch_domain.financial_transactions.domain_name
    ClientId   = local.account_id
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "opensearch_free_storage_space" {
  alarm_name          = "${var.opensearch_domain_name}-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/ES"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "2000" # 2GB in MB
  alarm_description   = "OpenSearch free storage space is low"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DomainName = aws_opensearch_domain.financial_transactions.domain_name
    ClientId   = local.account_id
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "opensearch_cpu_utilization" {
  alarm_name          = "${var.opensearch_domain_name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ES"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "OpenSearch CPU utilization is high"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DomainName = aws_opensearch_domain.financial_transactions.domain_name
    ClientId   = local.account_id
  }

  tags = local.common_tags
}
