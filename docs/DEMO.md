# Demo Guide

This guide helps you prepare and execute a successful demonstration of the AWS Glue Batch Processing Pipeline.

## Pre-Demo Checklist

### Infrastructure Verification

- [ ] All Terraform resources deployed successfully
- [ ] S3 buckets created and accessible
- [ ] DynamoDB table populated with customer data
- [ ] OpenSearch domain active and healthy
- [ ] Glue Job configured correctly
- [ ] IAM roles and permissions verified

### Data Verification

- [ ] At least 20 distinct customer accounts in DynamoDB
- [ ] At least 1000 transaction records in S3
- [ ] Data properly partitioned by year/month/day
- [ ] Sample queries tested on OpenSearch

### Code Preparation

- [ ] Glue Job JAR built and uploaded
- [ ] All source code reviewed and understood
- [ ] Comments added to complex sections
- [ ] Code walkthrough prepared

## Demo Script

### Part 1: Introduction (5 minutes)

**Talking Points**:

- Project overview and objectives
- Architecture components
- Technical challenges addressed
- Time invested in development

**Show**:

```bash
# Display project structure
tree -L 2 -I 'target|.terraform'

# Show README
cat README.md
```

### Part 2: Architecture Walkthrough (10 minutes)

**Talking Points**:

- Data flow from S3 → Glue → DynamoDB → OpenSearch
- Why MapPartitions for batch processing
- DynamoDB batch-get optimization
- OpenSearch indexing strategy

**Show**:

```bash
# Display architecture diagram
cat docs/ARCHITECTURE.md

# Show Terraform infrastructure
cd infrastructure
terraform show | head -50
```

### Part 3: Infrastructure as Code (10 minutes)

**Demonstrate Terraform Setup**:

```bash
# Show main configuration
cat infrastructure/main.tf

# Show S3 configuration
cat infrastructure/s3.tf

# Show DynamoDB configuration
cat infrastructure/dynamodb.tf

# Show Glue configuration
cat infrastructure/glue.tf

# Show OpenSearch configuration
cat infrastructure/opensearch.tf

# Display current state
terraform state list

# Show outputs
terraform output
```

**Explain**:

- Resource dependencies
- Security configurations
- Scalability considerations
- Cost optimization strategies

### Part 4: Data Generation (5 minutes)

**Show Test Data Creation**:

```bash
cd ../data-generation

# Show customer generation script
cat generate_customers.py | head -50

# Show transaction generation script
cat generate_transactions.py | head -50

# Display configuration
cat config.json

# Show sample generated data
aws dynamodb scan --table-name customer-registration-dev --max-items 3

# Show S3 data structure
aws s3 ls s3://YOUR-BUCKET/transactions/ --recursive | head -10
```

**Explain**:

- Data schema compliance
- Realistic data generation
- Volume requirements (1000+ transactions, 20+ accounts)

### Part 5: Glue Job Implementation (15 minutes)

**Code Walkthrough**:

```bash
cd ../glue-job

# Show build configuration
cat build.sbt

# Show main processor
cat src/main/scala/FinancialTransactionProcessor.scala

# Show data models
cat src/main/scala/models/Transaction.scala
cat src/main/scala/models/CustomerData.scala

# Show DynamoDB enrichment logic
cat src/main/scala/enrichment/DynamoDBEnricher.scala

# Show OpenSearch sink
cat src/main/scala/sink/OpenSearchSink.scala
```

**Key Points to Explain**:

1. **MapPartitions Implementation**:

   ```scala
   // Explain this pattern
   df.mapPartitions { partition =>
     // Extract unique account IDs from partition
     val accountIds = partition.map(_.numeroUnicoConta).toSet

     // Single batch-get for entire partition
     val customerData = batchGetFromDynamoDB(accountIds)

     // Enrich all transactions in partition
     partition.map(txn => enrichTransaction(txn, customerData))
   }
   ```

2. **DynamoDB Batch-Get**:

   ```scala
   // Explain batching strategy (max 100 items)
   def batchGetFromDynamoDB(accountIds: Set[String]): Map[String, CustomerData] = {
     accountIds.grouped(100).flatMap { batch =>
       // Batch-get request
       val request = new BatchGetItemRequest()
         .withRequestItems(...)

       dynamoDBClient.batchGetItem(request)
     }.toMap
   }
   ```

3. **CamelCase Transformation**:

   ```scala
   // Explain field name conversion
   def toCamelCase(snakeCase: String): String = {
     // Implementation details
   }
   ```

4. **Error Handling**:
   ```scala
   // Explain retry logic
   def withRetry[T](maxRetries: Int)(fn: => T): T = {
     // Exponential backoff implementation
   }
   ```

### Part 6: Live Execution (10 minutes)

**Run the Pipeline**:

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

# Get run ID
RUN_ID=$(aws glue get-job-runs --job-name $JOB_NAME --max-results 1 \
  --query 'JobRuns[0].Id' --output text)

echo "Job Run ID: $RUN_ID"

# Monitor status
watch -n 5 "aws glue get-job-run --job-name $JOB_NAME --run-id $RUN_ID \
  --query 'JobRun.JobRunState' --output text"
```

**Show CloudWatch Logs**:

```bash
# Tail logs in real-time
aws logs tail /aws-glue/jobs/output --follow --since 5m

# Show specific log events
aws logs filter-log-events \
  --log-group-name /aws-glue/jobs/output \
  --filter-pattern "Processing partition" \
  --max-items 10
```

### Part 7: Results Verification (10 minutes)

**Query OpenSearch**:

```bash
# Get OpenSearch endpoint
OPENSEARCH_ENDPOINT=$(cd infrastructure && terraform output -raw opensearch_endpoint)

# Check cluster health
curl -X GET "https://$OPENSEARCH_ENDPOINT/_cluster/health?pretty"

# Count total documents
curl -X GET "https://$OPENSEARCH_ENDPOINT/financial-transactions/_count?pretty"

# Show sample enriched documents
curl -X GET "https://$OPENSEARCH_ENDPOINT/financial-transactions/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 3,
    "query": { "match_all": {} }
  }'
```

**Demonstrate Data Enrichment**:

```bash
# Query showing enriched fields
curl -X GET "https://$OPENSEARCH_ENDPOINT/financial-transactions/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 1,
    "_source": [
      "codigoLancamento",
      "numeroUnicoConta",
      "valorTotalTransacao",
      "tipoTransacao",
      "nomeTitularConta",
      "dataNascimentoTitularConta",
      "zipCode"
    ],
    "query": { "match_all": {} }
  }'
```

**Show Analytics Queries**:

```bash
# Aggregate by transaction type
curl -X GET "https://$OPENSEARCH_ENDPOINT/financial-transactions/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "by_type": {
        "terms": { "field": "tipoTransacao" }
      }
    }
  }'

# Aggregate by product type
curl -X GET "https://$OPENSEARCH_ENDPOINT/financial-transactions/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "by_product": {
        "terms": { "field": "tipoProdutoTransacao" }
      }
    }
  }'

# Sum total transaction value
curl -X GET "https://$OPENSEARCH_ENDPOINT/financial-transactions/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "total_value": {
        "sum": { "field": "valorTotalTransacao" }
      }
    }
  }'
```

### Part 8: Performance Metrics (5 minutes)

**Show Job Metrics**:

```bash
# Get job run details
aws glue get-job-run \
  --job-name $JOB_NAME \
  --run-id $RUN_ID \
  --query 'JobRun.{
    State: JobRunState,
    Duration: ExecutionTime,
    DPUSeconds: DPUSeconds,
    StartedOn: StartedOn,
    CompletedOn: CompletedOn
  }' \
  --output table

# Show CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace Glue \
  --metric-name glue.driver.aggregate.numCompletedTasks \
  --dimensions Name=JobName,Value=$JOB_NAME Name=JobRunId,Value=$RUN_ID \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

**Discuss**:

- Processing time for 1000+ records
- DynamoDB batch-get efficiency
- OpenSearch indexing performance
- Cost per execution

### Part 9: Code Quality & Best Practices (5 minutes)

**Highlight**:

1. **Functional Programming**:
   - Immutable data structures
   - Pure functions
   - Type safety

2. **Error Handling**:
   - Try/Catch blocks
   - Retry mechanisms
   - Logging

3. **Performance Optimization**:
   - MapPartitions for batching
   - Efficient DynamoDB queries
   - Bulk OpenSearch inserts

4. **Code Organization**:
   - Separation of concerns
   - Modular design
   - Clear naming conventions

5. **Testing Considerations**:
   - Unit testable components
   - Integration test scenarios
   - Data validation

### Part 10: Q&A and Discussion (10 minutes)

**Prepared Answers for Common Questions**:

**Q: Why MapPartitions instead of map?**
A: MapPartitions allows us to batch DynamoDB requests per partition, reducing API calls from potentially thousands to just a few dozen, significantly improving performance and reducing costs.

**Q: How does the batch-get handle missing customer data?**
A: The enrichment logic includes null checks and default values. Transactions without matching customer data are still processed but with null enrichment fields, which can be filtered in OpenSearch queries.

**Q: What happens if the Glue Job fails mid-execution?**
A: Glue Jobs are idempotent by design. We can re-run for the same date partition. OpenSearch uses document IDs (codigoLancamento) to prevent duplicates through upsert operations.

**Q: How would you scale this for millions of records?**
A:

- Increase Glue workers (10-50)
- Optimize partition size
- Use larger OpenSearch cluster
- Consider DynamoDB provisioned capacity
- Implement incremental processing

**Q: What about data quality issues?**
A: We validate schemas during read, handle null values, and log data quality issues. In production, we'd add AWS Glue Data Quality rules.

**Q: Security considerations?**
A:

- VPC deployment for OpenSearch
- KMS encryption for all data stores
- IAM least privilege
- Audit logging via CloudTrail
- Network isolation

## Time Tracking Report

**Template for Demo**:

```
Development Time Breakdown:
- Infrastructure (Terraform): X hours
- Glue Job (Scala): Y hours
- Data Generation: Z hours
- Testing & Debugging: W hours
- Documentation: V hours
Total: XX hours
```

## Demo Tips

### Do's:

✅ Test everything before the demo
✅ Have backup plans for live demos
✅ Explain your thought process
✅ Show both code and results
✅ Be prepared for questions
✅ Demonstrate understanding of every line of code
✅ Highlight challenges overcome
✅ Show monitoring and logging

### Don'ts:

❌ Rush through explanations
❌ Skip error handling discussion
❌ Ignore performance considerations
❌ Forget to mention limitations
❌ Claim you used AI (prohibited)
❌ Be unprepared for code questions

## Backup Plans

### If Live Execution Fails:

1. **Have Pre-recorded Results**:
   - Screenshots of successful runs
   - Sample OpenSearch queries and results
   - CloudWatch logs from previous runs

2. **Explain the Issue**:
   - Show debugging approach
   - Demonstrate troubleshooting skills
   - Discuss how you'd resolve it

3. **Show Alternative Evidence**:
   - Unit test results
   - Local Scala execution
   - Sample data transformations

## Post-Demo Deliverables

**Zip File Contents**:

```
financial-batch-processor.zip
├── infrastructure/          # All Terraform files
├── glue-job/               # All Scala source code
├── data-generation/        # Python scripts
├── docs/                   # Documentation
├── README.md
├── .gitignore
├── Makefile
└── TIME_TRACKING.md        # Your time investment report
```

**Create Deliverable**:

```bash
# From project root
zip -r financial-batch-processor.zip . \
  -x "*.terraform/*" \
  -x "*/target/*" \
  -x "*/__pycache__/*" \
  -x "*.tfstate*" \
  -x "*/.git/*"

# Verify contents
unzip -l financial-batch-processor.zip
```

## Success Criteria

- [ ] All functional requirements met
- [ ] All non-functional requirements met
- [ ] Clean, well-documented code
- [ ] Successful live execution
- [ ] Clear explanation of architecture
- [ ] Demonstrated understanding of all code
- [ ] Professional presentation
- [ ] Time tracking reported

## Final Checklist

Before the demo:

- [ ] Practice the demo at least twice
- [ ] Verify all AWS resources are running
- [ ] Test all commands in the script
- [ ] Prepare answers to likely questions
- [ ] Have backup screenshots ready
- [ ] Charge laptop and have charger
- [ ] Test screen sharing if remote
- [ ] Review all code one final time
- [ ] Prepare time tracking report
- [ ] Create deliverable zip file

Good luck with your demo! 🚀
