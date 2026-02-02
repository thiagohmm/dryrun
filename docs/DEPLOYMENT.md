# Deployment Guide

This guide provides step-by-step instructions for deploying the AWS Glue Batch Processing Pipeline.

## Prerequisites

### Required Tools

1. **AWS CLI** (v2.x)

   ```bash
   aws --version
   # aws-cli/2.x.x
   ```

2. **Terraform** (>= 1.0)

   ```bash
   terraform --version
   # Terraform v1.x.x
   ```

3. **Python** (>= 3.8)

   ```bash
   python3 --version
   # Python 3.8+
   ```

4. **Scala & SBT**
   ```bash
   scala -version
   # Scala code runner version 2.12.x
   sbt --version
   # sbt version 1.x.x
   ```

### AWS Account Setup

1. **Configure AWS Credentials**

   ```bash
   aws configure
   # AWS Access Key ID: YOUR_ACCESS_KEY
   # AWS Secret Access Key: YOUR_SECRET_KEY
   # Default region name: us-east-1
   # Default output format: json
   ```

2. **Verify Permissions**
   Required IAM permissions:
   - S3: Full access
   - DynamoDB: Full access
   - OpenSearch: Full access
   - Glue: Full access
   - IAM: Create roles and policies
   - CloudWatch: Logs and metrics

## Deployment Steps

### Step 1: Clone and Setup Project

```bash
# Navigate to project directory
cd /path/to/dryRun

# Verify project structure
ls -la
```

### Step 2: Configure Terraform Variables

```bash
cd infrastructure

# Create terraform.tfvars from example
cp terraform.tfvars.example terraform.tfvars

# Edit variables
nano terraform.tfvars
```

**terraform.tfvars** example:

```hcl
aws_region = "us-east-1"
project_name = "financial-batch-processor"
environment = "dev"

# S3 Configuration
s3_bucket_name = "financial-transactions-dev-12345"

# DynamoDB Configuration
dynamodb_table_name = "customer-registration-dev"
dynamodb_billing_mode = "PAY_PER_REQUEST"

# OpenSearch Configuration
opensearch_domain_name = "financial-txns-dev"
opensearch_instance_type = "t3.small.search"
opensearch_instance_count = 1
opensearch_ebs_volume_size = 10

# Glue Configuration
glue_job_name = "financial-transaction-processor"
glue_worker_type = "G.1X"
glue_number_of_workers = 2
glue_max_retries = 1

# Network (Optional - for VPC deployment)
# vpc_id = "vpc-xxxxx"
# subnet_ids = ["subnet-xxxxx", "subnet-yyyyy"]

# Tags
tags = {
  Project = "FinancialBatchProcessor"
  Environment = "Development"
  ManagedBy = "Terraform"
}
```

### Step 3: Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan deployment
terraform plan -out=tfplan

# Review the plan carefully
# Apply infrastructure
terraform apply tfplan

# Save outputs
terraform output > ../outputs.txt
```

**Expected Resources Created**:

- S3 bucket for transactions
- S3 bucket for Glue scripts
- DynamoDB table for customer data
- OpenSearch domain
- Glue Job definition
- IAM roles and policies
- CloudWatch log groups

### Step 4: Generate Test Data

```bash
cd ../data-generation

# Install Python dependencies
pip install -r requirements.txt

# Configure data generation
nano config.json
```

**config.json**:

```json
{
  "num_customers": 20,
  "num_transactions": 1000,
  "start_date": "2024-01-01",
  "end_date": "2024-01-31",
  "aws_region": "us-east-1",
  "dynamodb_table": "customer-registration-dev",
  "s3_bucket": "financial-transactions-dev-12345",
  "s3_prefix": "transactions"
}
```

```bash
# Generate customer data and upload to DynamoDB
python generate_customers.py

# Generate transaction data and upload to S3
python generate_transactions.py

# Verify data
aws dynamodb scan --table-name customer-registration-dev --max-items 5
aws s3 ls s3://financial-transactions-dev-12345/transactions/ --recursive
```

### Step 5: Build and Deploy Glue Job

```bash
cd ../glue-job

# Clean previous builds
sbt clean

# Compile and package
sbt package

# Verify JAR created
ls -lh target/scala-2.12/financial-transaction-processor_2.12-1.0.jar
```

```bash
# Get Glue scripts bucket from Terraform output
GLUE_BUCKET=$(cd ../infrastructure && terraform output -raw glue_scripts_bucket)

# Upload JAR to S3
aws s3 cp target/scala-2.12/financial-transaction-processor_2.12-1.0.jar \
  s3://$GLUE_BUCKET/scripts/financial-transaction-processor_2.12-1.0.jar

# Verify upload
aws s3 ls s3://$GLUE_BUCKET/scripts/
```

### Step 6: Update Glue Job with Script Location

```bash
cd ../infrastructure

# Update Glue job with script location
JOB_NAME=$(terraform output -raw glue_job_name)
SCRIPT_LOCATION="s3://$GLUE_BUCKET/scripts/financial-transaction-processor_2.12-1.0.jar"

aws glue update-job \
  --job-name $JOB_NAME \
  --job-update '{
    "Command": {
      "Name": "glueetl",
      "ScriptLocation": "'$SCRIPT_LOCATION'",
      "PythonVersion": "3"
    }
  }'
```

### Step 7: Run Glue Job

```bash
# Start job run for specific date
aws glue start-job-run \
  --job-name $JOB_NAME \
  --arguments '{
    "--year":"2024",
    "--month":"01",
    "--day":"15",
    "--s3_bucket":"'$S3_BUCKET'",
    "--dynamodb_table":"customer-registration-dev",
    "--opensearch_endpoint":"'$OPENSEARCH_ENDPOINT'",
    "--opensearch_index":"financial-transactions"
  }'

# Save job run ID
JOB_RUN_ID=$(aws glue get-job-runs --job-name $JOB_NAME --max-results 1 --query 'JobRuns[0].Id' --output text)

echo "Job Run ID: $JOB_RUN_ID"
```

### Step 8: Monitor Job Execution

```bash
# Check job status
aws glue get-job-run \
  --job-name $JOB_NAME \
  --run-id $JOB_RUN_ID \
  --query 'JobRun.JobRunState' \
  --output text

# View CloudWatch logs
LOG_GROUP="/aws-glue/jobs/output"
aws logs tail $LOG_GROUP --follow

# Check for errors
aws logs filter-log-events \
  --log-group-name $LOG_GROUP \
  --filter-pattern "ERROR"
```

### Step 9: Verify Data in OpenSearch

```bash
# Get OpenSearch endpoint
OPENSEARCH_ENDPOINT=$(cd infrastructure && terraform output -raw opensearch_endpoint)

# Check cluster health
curl -X GET "https://$OPENSEARCH_ENDPOINT/_cluster/health?pretty"

# Count documents in index
curl -X GET "https://$OPENSEARCH_ENDPOINT/financial-transactions/_count?pretty"

# Sample query
curl -X GET "https://$OPENSEARCH_ENDPOINT/financial-transactions/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 5,
    "query": {
      "match_all": {}
    }
  }'

# Query by transaction type
curl -X GET "https://$OPENSEARCH_ENDPOINT/financial-transactions/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "term": {
        "tipoTransacao": "CREDITO"
      }
    }
  }'
```

## Troubleshooting

### Common Issues

#### 1. Terraform Apply Fails

**Error**: "Error creating S3 bucket: BucketAlreadyExists"

```bash
# Solution: Change bucket name in terraform.tfvars
# S3 bucket names must be globally unique
```

**Error**: "Error creating OpenSearch domain: InvalidTypeException"

```bash
# Solution: Check instance type availability in your region
# Use: aws opensearch list-instance-types --region us-east-1
```

#### 2. Glue Job Fails

**Error**: "Class not found"

```bash
# Solution: Verify JAR uploaded correctly
aws s3 ls s3://$GLUE_BUCKET/scripts/

# Re-upload if needed
sbt clean package
aws s3 cp target/scala-2.12/*.jar s3://$GLUE_BUCKET/scripts/
```

**Error**: "Access Denied to DynamoDB"

```bash
# Solution: Check IAM role permissions
aws iam get-role-policy \
  --role-name glue-job-role \
  --policy-name dynamodb-access
```

#### 3. Data Generation Issues

**Error**: "Unable to locate credentials"

```bash
# Solution: Configure AWS credentials
aws configure
```

**Error**: "Table does not exist"

```bash
# Solution: Verify DynamoDB table created
aws dynamodb describe-table --table-name customer-registration-dev
```

#### 4. OpenSearch Access Issues

**Error**: "Connection timeout"

```bash
# Solution: Check security group rules
# If using VPC, ensure proper network configuration
# If public, verify IP whitelist in access policy
```

### Validation Checklist

- [ ] Terraform apply completed successfully
- [ ] S3 buckets created and accessible
- [ ] DynamoDB table created with correct schema
- [ ] OpenSearch domain active and healthy
- [ ] Glue Job created with correct configuration
- [ ] IAM roles have necessary permissions
- [ ] Test data generated (20+ customers, 1000+ transactions)
- [ ] Glue Job JAR uploaded to S3
- [ ] Glue Job executed successfully
- [ ] Data visible in OpenSearch
- [ ] CloudWatch logs available

## Cleanup

To destroy all resources:

```bash
# Delete OpenSearch index data (optional)
curl -X DELETE "https://$OPENSEARCH_ENDPOINT/financial-transactions"

# Empty S3 buckets
aws s3 rm s3://$S3_BUCKET --recursive
aws s3 rm s3://$GLUE_BUCKET --recursive

# Destroy infrastructure
cd infrastructure
terraform destroy

# Confirm destruction
# Type: yes
```

## Production Deployment Considerations

### Security Hardening

1. **Enable VPC for OpenSearch**
   - Deploy in private subnet
   - Use VPC endpoints
   - Restrict security group rules

2. **Enable Encryption**
   - S3: SSE-KMS
   - DynamoDB: KMS encryption
   - OpenSearch: Encryption at rest and in transit

3. **IAM Best Practices**
   - Use least privilege principle
   - Enable MFA for sensitive operations
   - Rotate credentials regularly

### High Availability

1. **Multi-AZ Deployment**
   - OpenSearch: 3 nodes across AZs
   - DynamoDB: Global tables (optional)

2. **Backup and Recovery**
   - Enable DynamoDB point-in-time recovery
   - Configure OpenSearch automated snapshots
   - S3 versioning and lifecycle policies

### Monitoring and Alerting

1. **CloudWatch Alarms**
   - Glue Job failures
   - DynamoDB throttling
   - OpenSearch cluster health
   - High error rates

2. **Dashboards**
   - Create CloudWatch dashboard
   - Monitor key metrics
   - Set up SNS notifications

### Cost Optimization

1. **Right-sizing**
   - Start with smaller instances
   - Monitor and adjust based on metrics
   - Use Savings Plans for predictable workloads

2. **Data Lifecycle**
   - Archive old S3 data to Glacier
   - Delete old OpenSearch indices
   - Use DynamoDB on-demand for variable loads

## Next Steps

After successful deployment:

1. Review [DEMO.md](DEMO.md) for demo preparation
2. Test with different date partitions
3. Monitor performance metrics
4. Optimize based on actual workload
5. Implement additional features as needed
