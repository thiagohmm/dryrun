# Quick Reference Guide

This guide provides quick access to commonly used commands for the AWS Glue Batch Processing Pipeline.

## Prerequisites Check

```bash
# Check AWS CLI
aws --version

# Check Terraform
terraform --version

# Check Python
python3 --version

# Check Scala
scala -version

# Check SBT
sbt --version

# Verify AWS credentials
aws sts get-caller-identity
```

## Infrastructure Commands

### Terraform

```bash
# Navigate to infrastructure directory
cd infrastructure

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Format Terraform files
terraform fmt

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply

# Show current state
terraform show

# List resources
terraform state list

# Get outputs
terraform output

# Destroy infrastructure
terraform destroy
```

### Get Specific Outputs

```bash
# Get S3 bucket name
terraform output -raw s3_transactions_bucket

# Get Glue scripts bucket
terraform output -raw glue_scripts_bucket

# Get DynamoDB table name
terraform output -raw dynamodb_table_name

# Get OpenSearch endpoint
terraform output -raw opensearch_endpoint

# Get Glue job name
terraform output -raw glue_job_name
```

## Data Generation Commands

### Setup

```bash
# Navigate to data generation directory
cd data-generation

# Install dependencies
pip install -r requirements.txt

# Or with virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### Generate Data

```bash
# Generate customer data
python generate_customers.py

# Generate transaction data
python generate_transactions.py

# Generate both
python generate_customers.py && python generate_transactions.py
```

### Verify Data

```bash
# Check DynamoDB
aws dynamodb scan --table-name customer-registration-dev --max-items 5

# Count DynamoDB items
aws dynamodb scan --table-name customer-registration-dev --select COUNT

# List S3 files
aws s3 ls s3://YOUR-BUCKET/transactions/ --recursive

# Count S3 objects
aws s3 ls s3://YOUR-BUCKET/transactions/ --recursive | wc -l

# Download sample S3 file
aws s3 cp s3://YOUR-BUCKET/transactions/year=2024/month=01/day=15/transactions_xxx.json ./sample.json
```

## Glue Job Commands

### Build

```bash
# Navigate to glue-job directory
cd glue-job

# Clean previous builds
sbt clean

# Compile
sbt compile

# Run tests (if any)
sbt test

# Package JAR
sbt package

# Create assembly JAR (fat JAR)
sbt assembly

# Check JAR location
ls -lh target/scala-2.12/
```

### Deploy

```bash
# Set variables
GLUE_BUCKET=$(cd ../infrastructure && terraform output -raw glue_scripts_bucket)
JAR_FILE="target/scala-2.12/financial-transaction-processor_2.12-1.0.jar"

# Upload JAR to S3
aws s3 cp $JAR_FILE s3://$GLUE_BUCKET/scripts/

# Verify upload
aws s3 ls s3://$GLUE_BUCKET/scripts/

# Update Glue job script location
JOB_NAME=$(cd ../infrastructure && terraform output -raw glue_job_name)
aws glue update-job --job-name $JOB_NAME \
  --job-update '{
    "Command": {
      "Name": "glueetl",
      "ScriptLocation": "s3://'$GLUE_BUCKET'/scripts/financial-transaction-processor_2.12-1.0.jar"
    }
  }'
```

### Execute

```bash
# Get job name
JOB_NAME=$(cd infrastructure && terraform output -raw glue_job_name)

# Start job run
aws glue start-job-run \
  --job-name $JOB_NAME \
  --arguments '{
    "--year":"2024",
    "--month":"01",
    "--day":"15"
  }'

# Start job run with all parameters
aws glue start-job-run \
  --job-name $JOB_NAME \
  --arguments '{
    "--year":"2024",
    "--month":"01",
    "--day":"15",
    "--s3_bucket":"YOUR-BUCKET",
    "--dynamodb_table":"customer-registration-dev",
    "--opensearch_endpoint":"YOUR-ENDPOINT",
    "--opensearch_index":"financial-transactions",
    "--aws_region":"us-east-1"
  }'

# Get latest job run ID
RUN_ID=$(aws glue get-job-runs --job-name $JOB_NAME --max-results 1 \
  --query 'JobRuns[0].Id' --output text)

echo "Job Run ID: $RUN_ID"
```

### Monitor

```bash
# Check job status
aws glue get-job-run \
  --job-name $JOB_NAME \
  --run-id $RUN_ID \
  --query 'JobRun.JobRunState' \
  --output text

# Get job run details
aws glue get-job-run \
  --job-name $JOB_NAME \
  --run-id $RUN_ID

# List all job runs
aws glue get-job-runs --job-name $JOB_NAME

# Watch job status (updates every 10 seconds)
watch -n 10 "aws glue get-job-run --job-name $JOB_NAME --run-id $RUN_ID \
  --query 'JobRun.JobRunState' --output text"
```

## CloudWatch Logs Commands

```bash
# List log groups
aws logs describe-log-groups --log-group-name-prefix /aws-glue

# Tail logs (follow mode)
aws logs tail /aws-glue/jobs/output --follow

# Tail logs since specific time
aws logs tail /aws-glue/jobs/output --follow --since 30m

# Filter logs for errors
aws logs filter-log-events \
  --log-group-name /aws-glue/jobs/output \
  --filter-pattern "ERROR"

# Filter logs for specific job run
aws logs filter-log-events \
  --log-group-name /aws-glue/jobs/output \
  --filter-pattern "$RUN_ID"

# Get recent log events
aws logs tail /aws-glue/jobs/output --since 1h
```

## OpenSearch Commands

```bash
# Get OpenSearch endpoint
OPENSEARCH_ENDPOINT=$(cd infrastructure && terraform output -raw opensearch_endpoint)

# Check cluster health
curl -X GET "https://$OPENSEARCH_ENDPOINT/_cluster/health?pretty"

# List indices
curl -X GET "https://$OPENSEARCH_ENDPOINT/_cat/indices?v"

# Count documents
curl -X GET "https://$OPENSEARCH_ENDPOINT/financial-transactions/_count?pretty"

# Search all documents (limit 10)
curl -X GET "https://$OPENSEARCH_ENDPOINT/financial-transactions/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{"size": 10, "query": {"match_all": {}}}'

# Search by transaction type
curl -X GET "https://$OPENSEARCH_ENDPOINT/financial-transactions/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "term": {
        "tipoTransacao": "CREDITO"
      }
    }
  }'

# Aggregate by transaction type
curl -X GET "https://$OPENSEARCH_ENDPOINT/financial-transactions/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "by_type": {
        "terms": {"field": "tipoTransacao"}
      }
    }
  }'

# Get index mapping
curl -X GET "https://$OPENSEARCH_ENDPOINT/financial-transactions/_mapping?pretty"

# Delete index (careful!)
curl -X DELETE "https://$OPENSEARCH_ENDPOINT/financial-transactions"
```

## DynamoDB Commands

```bash
# Get table name
TABLE_NAME=$(cd infrastructure && terraform output -raw dynamodb_table_name)

# Describe table
aws dynamodb describe-table --table-name $TABLE_NAME

# Scan table (first 10 items)
aws dynamodb scan --table-name $TABLE_NAME --max-items 10

# Count items
aws dynamodb scan --table-name $TABLE_NAME --select COUNT

# Get specific item
aws dynamodb get-item \
  --table-name $TABLE_NAME \
  --key '{"numero_unico_conta": {"S": "YOUR-ACCOUNT-ID"}}'

# Batch get items
aws dynamodb batch-get-item \
  --request-items '{
    "'$TABLE_NAME'": {
      "Keys": [
        {"numero_unico_conta": {"S": "ACCOUNT-ID-1"}},
        {"numero_unico_conta": {"S": "ACCOUNT-ID-2"}}
      ]
    }
  }'

# Query by partition key
aws dynamodb query \
  --table-name $TABLE_NAME \
  --key-condition-expression "numero_unico_conta = :account_id" \
  --expression-attribute-values '{":account_id": {"S": "YOUR-ACCOUNT-ID"}}'
```

## S3 Commands

```bash
# Get bucket name
BUCKET_NAME=$(cd infrastructure && terraform output -raw s3_transactions_bucket)

# List all objects
aws s3 ls s3://$BUCKET_NAME/transactions/ --recursive

# List specific partition
aws s3 ls s3://$BUCKET_NAME/transactions/year=2024/month=01/day=15/

# Copy file from S3
aws s3 cp s3://$BUCKET_NAME/transactions/year=2024/month=01/day=15/file.json ./

# Upload file to S3
aws s3 cp local-file.json s3://$BUCKET_NAME/transactions/year=2024/month=01/day=15/

# Sync directory to S3
aws s3 sync ./local-dir s3://$BUCKET_NAME/transactions/

# Remove all objects (careful!)
aws s3 rm s3://$BUCKET_NAME/transactions/ --recursive
```

## Makefile Commands

```bash
# Show available commands
make help

# Initialize Terraform
make init

# Plan Terraform changes
make plan

# Apply infrastructure
make apply

# Generate test data
make generate-data

# Build Glue Job
make build-glue

# Deploy Glue Job
make deploy-glue

# Run Glue Job
make run-glue

# Clean build artifacts
make clean

# Destroy infrastructure
make destroy
```

## Troubleshooting Commands

### Check AWS Resources

```bash
# List S3 buckets
aws s3 ls

# List DynamoDB tables
aws dynamodb list-tables

# List OpenSearch domains
aws opensearch list-domain-names

# List Glue jobs
aws glue list-jobs

# Check IAM role
aws iam get-role --role-name glue-job-role
```

### Debug Glue Job

```bash
# Get job definition
aws glue get-job --job-name $JOB_NAME

# Get job run error
aws glue get-job-run \
  --job-name $JOB_NAME \
  --run-id $RUN_ID \
  --query 'JobRun.ErrorMessage'

# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace Glue \
  --metric-name glue.driver.aggregate.numCompletedTasks \
  --dimensions Name=JobName,Value=$JOB_NAME Name=JobRunId,Value=$RUN_ID \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

### Cleanup Commands

```bash
# Delete all objects from S3 bucket
aws s3 rm s3://$BUCKET_NAME --recursive

# Delete DynamoDB table items (scan and delete)
aws dynamodb scan --table-name $TABLE_NAME \
  --attributes-to-get numero_unico_conta \
  --query 'Items[*].numero_unico_conta.S' \
  --output text | xargs -I {} aws dynamodb delete-item \
  --table-name $TABLE_NAME \
  --key '{"numero_unico_conta": {"S": "{}"}}'

# Delete OpenSearch index
curl -X DELETE "https://$OPENSEARCH_ENDPOINT/financial-transactions"

# Stop running Glue job
aws glue batch-stop-job-run \
  --job-name $JOB_NAME \
  --job-run-ids $RUN_ID
```

## Environment Variables

```bash
# Set common environment variables
export AWS_REGION=us-east-1
export AWS_PROFILE=default
export GLUE_JOB_NAME=$(cd infrastructure && terraform output -raw glue_job_name)
export S3_BUCKET=$(cd infrastructure && terraform output -raw s3_transactions_bucket)
export DYNAMODB_TABLE=$(cd infrastructure && terraform output -raw dynamodb_table_name)
export OPENSEARCH_ENDPOINT=$(cd infrastructure && terraform output -raw opensearch_endpoint)

# Save to .env file
cat > .env << EOF
AWS_REGION=$AWS_REGION
GLUE_JOB_NAME=$GLUE_JOB_NAME
S3_BUCKET=$S3_BUCKET
DYNAMODB_TABLE=$DYNAMODB_TABLE
OPENSEARCH_ENDPOINT=$OPENSEARCH_ENDPOINT
EOF

# Load from .env file
source .env
```

## Useful One-Liners

```bash
# Complete deployment pipeline
cd infrastructure && terraform apply -auto-approve && \
cd ../data-generation && python generate_customers.py && python generate_transactions.py && \
cd ../glue-job && sbt clean package && \
aws s3 cp target/scala-2.12/*.jar s3://$(cd ../infrastructure && terraform output -raw glue_scripts_bucket)/scripts/

# Run job and tail logs
aws glue start-job-run --job-name $JOB_NAME --arguments '{"--year":"2024","--month":"01","--day":"15"}' && \
aws logs tail /aws-glue/jobs/output --follow

# Check pipeline status
echo "S3 Files: $(aws s3 ls s3://$S3_BUCKET/transactions/ --recursive | wc -l)" && \
echo "DynamoDB Items: $(aws dynamodb scan --table-name $DYNAMODB_TABLE --select COUNT --query 'Count' --output text)" && \
echo "OpenSearch Docs: $(curl -s https://$OPENSEARCH_ENDPOINT/financial-transactions/_count | jq '.count')"
```

## Tips and Best Practices

1. **Always check AWS region**: Ensure you're working in the correct region
2. **Use environment variables**: Set common values to avoid repetition
3. **Monitor costs**: Check AWS Cost Explorer regularly
4. **Clean up resources**: Destroy infrastructure when not in use
5. **Version control**: Commit changes regularly
6. **Test incrementally**: Test each component before integration
7. **Check logs**: Always review CloudWatch logs for errors
8. **Backup data**: Keep local copies of generated data
9. **Document changes**: Update documentation as you modify code
10. **Use Makefile**: Leverage automation for common tasks

---

**Quick Help**: Run `make help` for available automation commands
