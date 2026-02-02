# Architecture Documentation

## System Overview

This document describes the architecture of the AWS Glue Batch Processing Pipeline for financial transactions.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                          AWS Cloud Environment                       │
│                                                                       │
│  ┌──────────────┐                                                    │
│  │   S3 Bucket  │                                                    │
│  │              │                                                    │
│  │ Partitioned  │                                                    │
│  │ by Date:     │                                                    │
│  │ /year=/month │                                                    │
│  │ /day/        │                                                    │
│  │              │                                                    │
│  │ JSON Files   │                                                    │
│  └──────┬───────┘                                                    │
│         │                                                            │
│         │ Read                                                       │
│         ▼                                                            │
│  ┌──────────────────────────────────────────┐                       │
│  │      AWS Glue Job (Scala 2.12)          │                       │
│  │                                          │                       │
│  │  ┌────────────────────────────────────┐ │                       │
│  │  │  1. Read from S3                   │ │                       │
│  │  │  2. Parse JSON to DataFrame        │ │                       │
│  │  │  3. MapPartitions Processing:      │ │                       │
│  │  │     - Group by partition           │ │                       │
│  │  │     - Extract unique account IDs   │ │                       │
│  │  │     - Batch-get from DynamoDB      │ │◄──────┐              │
│  │  │     - Enrich transactions          │ │       │              │
│  │  │     - Transform to camelCase       │ │       │              │
│  │  │  4. Write to OpenSearch            │ │       │              │
│  │  └────────────────────────────────────┘ │       │              │
│  └──────────────┬───────────────────────────┘       │              │
│                 │                                   │              │
│                 │                            ┌──────┴──────────┐   │
│                 │                            │   DynamoDB      │   │
│                 │                            │                 │   │
│                 │                            │  Customer Data  │   │
│                 │                            │  Table          │   │
│                 │                            │                 │   │
│                 │                            │  Batch-Get API  │   │
│                 │                            └─────────────────┘   │
│                 │                                                  │
│                 │ Write                                            │
│                 ▼                                                  │
│  ┌──────────────────────────────┐                                 │
│  │     OpenSearch Domain        │                                 │
│  │                              │                                 │
│  │  Index: financial-txns       │                                 │
│  │  Format: camelCase JSON      │                                 │
│  │                              │                                 │
│  │  Enriched Transaction Data   │                                 │
│  └──────────────────────────────┘                                 │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. S3 Bucket (Data Lake)

**Purpose**: Store raw financial transaction data

**Structure**:

```
s3://financial-transactions-bucket/
└── transactions/
    └── year=2024/
        └── month=01/
            └── day=15/
                ├── transactions_001.json
                ├── transactions_002.json
                └── transactions_003.json
```

**Data Format**: JSON (snake_case)

**Partitioning Strategy**:

- Year/Month/Day partitioning for efficient querying
- Enables incremental processing
- Supports time-based data retention policies

### 2. AWS Glue Job

**Runtime**: Glue 4.0
**Language**: Scala 2.12
**Worker Type**: G.1X (recommended) or G.2X for larger datasets
**Number of Workers**: 2-10 (configurable based on data volume)

**Processing Flow**:

1. **Data Ingestion**
   - Read partitioned JSON files from S3
   - Convert to Spark DataFrame
   - Validate schema

2. **Batch Enrichment (MapPartitions)**

   ```scala
   df.mapPartitions { partition =>
     val accountIds = partition.map(_.numero_unico_conta).toSet
     val customerData = batchGetFromDynamoDB(accountIds)
     partition.map(txn => enrichTransaction(txn, customerData))
   }
   ```

3. **Data Transformation**
   - Convert snake_case to camelCase
   - Merge transaction and customer data
   - Apply business rules

4. **Data Loading**
   - Bulk insert to OpenSearch
   - Handle errors and retries

**Key Features**:

- **MapPartitions**: Minimizes DynamoDB calls by batching per partition
- **Batch-Get**: Retrieves up to 100 items per DynamoDB request
- **Error Handling**: Retry logic with exponential backoff
- **Logging**: CloudWatch integration for monitoring

### 3. DynamoDB Table

**Table Name**: customer-registration
**Primary Key**: numero_unico_conta (String)
**Capacity Mode**: On-Demand (auto-scaling)

**Attributes**:

- numero_unico_conta (PK)
- nome_titular_conta
- data_nascimento_titular_conta
- zip-code
- data_criacao_registro

**Access Pattern**:

- Batch-get operations (up to 100 items)
- Read-heavy workload
- Low latency requirements

### 4. OpenSearch Domain

**Version**: OpenSearch 2.x
**Instance Type**: t3.small.search (development) or r6g.large.search (production)
**Number of Nodes**: 1 (dev) or 3 (prod with HA)
**Storage**: EBS (gp3)

**Index Configuration**:

```json
{
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 1,
    "refresh_interval": "30s"
  },
  "mappings": {
    "properties": {
      "codigoLancamento": { "type": "keyword" },
      "numeroUnicoConta": { "type": "keyword" },
      "valorTotalTransacao": { "type": "double" },
      "dataCompletaTransacao": { "type": "date" },
      "tipoTransacao": { "type": "keyword" },
      "tipoProdutoTransacao": { "type": "keyword" },
      "nomeTitularConta": { "type": "text" },
      "dataNascimentoTitularConta": { "type": "date" },
      "zipCode": { "type": "keyword" }
    }
  }
}
```

## Data Flow

### Step-by-Step Processing

1. **Trigger**: Manual or scheduled (EventBridge)
2. **Read**: Glue Job reads from S3 partition (e.g., year=2024/month=01/day=15)
3. **Parse**: JSON files converted to Spark DataFrame
4. **Partition**: Data distributed across Spark partitions
5. **Enrich**: For each partition:
   - Extract unique account IDs
   - Batch-get customer data from DynamoDB (max 100 per request)
   - Join transaction with customer data
6. **Transform**: Convert to camelCase JSON
7. **Load**: Bulk insert to OpenSearch index
8. **Complete**: Job logs metrics and completes

## Performance Considerations

### Optimization Strategies

1. **Batch Size Optimization**
   - DynamoDB: 100 items per batch-get
   - OpenSearch: 1000 documents per bulk request
   - Spark partitions: Based on data size (128MB default)

2. **Parallelism**
   - Spark executors: 2-10 workers
   - DynamoDB concurrent requests: Controlled by partition count
   - OpenSearch bulk threads: 2-4 per worker

3. **Memory Management**
   - Worker memory: 8GB (G.1X) or 16GB (G.2X)
   - Partition size: Keep under 128MB
   - Cache customer data within partition

4. **Error Handling**
   - Retry failed DynamoDB requests (3 attempts)
   - Dead letter queue for failed records
   - CloudWatch alarms for job failures

## Security

### IAM Roles and Policies

1. **Glue Job Role**
   - S3: Read from transactions bucket
   - DynamoDB: BatchGetItem permission
   - OpenSearch: Write access
   - CloudWatch: Logs and metrics

2. **Network Security**
   - VPC: Optional (can run in public subnet)
   - Security Groups: Restrict OpenSearch access
   - Encryption: At rest (S3, DynamoDB, OpenSearch) and in transit (TLS)

3. **Data Protection**
   - S3 bucket encryption (SSE-S3 or SSE-KMS)
   - DynamoDB encryption at rest
   - OpenSearch encryption at rest and node-to-node

## Monitoring and Logging

### CloudWatch Metrics

- Glue Job: Duration, DPU hours, success/failure rate
- DynamoDB: Read capacity, throttling events
- OpenSearch: Indexing rate, search latency, cluster health

### Logging

- Glue Job logs: CloudWatch Logs
- Application logs: Custom metrics and structured logging
- Audit logs: CloudTrail for API calls

## Scalability

### Horizontal Scaling

- **Glue Workers**: Increase from 2 to 10+ based on data volume
- **DynamoDB**: On-demand mode auto-scales
- **OpenSearch**: Add data nodes for larger datasets

### Vertical Scaling

- **Glue Worker Type**: Upgrade from G.1X to G.2X
- **OpenSearch Instance**: Upgrade to larger instance types

## Cost Optimization

1. **Glue**: Use appropriate worker count and type
2. **DynamoDB**: On-demand for variable workloads
3. **OpenSearch**: Right-size instances, use reserved instances
4. **S3**: Lifecycle policies for old data (Glacier/Deep Archive)

## Disaster Recovery

- **S3**: Cross-region replication (optional)
- **DynamoDB**: Point-in-time recovery enabled
- **OpenSearch**: Automated snapshots to S3
- **Glue Job**: Version control in Git, JAR backup in S3

## Future Enhancements

1. **Real-time Processing**: Add Kinesis Data Streams
2. **Data Quality**: Implement AWS Glue Data Quality
3. **Orchestration**: Use Step Functions for complex workflows
4. **ML Integration**: Add SageMaker for fraud detection
5. **API Layer**: Add API Gateway for OpenSearch queries
