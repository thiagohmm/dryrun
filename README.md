# AWS Glue Batch Processing Pipeline

## Overview

This project implements a batch processing pipeline for financial transactions using AWS Glue, DynamoDB, and OpenSearch. The solution reads transaction data from S3, enriches it with customer information from DynamoDB, and stores the enriched data in OpenSearch for analytics.

## Architecture

```
S3 Bucket (JSON) → AWS Glue Job (Scala) → DynamoDB (Batch Enrichment) → OpenSearch
```

### Components

1. **S3 Bucket**: Stores financial transaction data partitioned by year/month/day
2. **AWS Glue Job**: Scala-based ETL job using MapPartitions for batch processing
3. **DynamoDB**: Customer registration data for enrichment
4. **OpenSearch**: Final storage for enriched transactions

## Data Schemas

### S3 Transaction Data

```json
{
  "codigo_lancamento": "uuid",
  "numero_unico_conta": "uuid",
  "valor_total_transacao": 100.5,
  "data_completa_transacao": "2024-01-15T10:30:00Z",
  "tipo_transacao": "CREDITO",
  "tipo_produto_transacao": "PIX"
}
```

### DynamoDB Customer Data

```json
{
  "numero_unico_conta": "uuid",
  "nome_titular_conta": "John Doe",
  "data_nascimento_titular_conta": "1990-01-15T00:00:00Z",
  "zip-code": "12345-678",
  "data_criacao_registro": "2023-01-01"
}
```

### OpenSearch Enriched Data (camelCase)

```json
{
  "codigoLancamento": "uuid",
  "numeroUnicoConta": "uuid",
  "valorTotalTransacao": 100.5,
  "dataCompletaTransacao": "2024-01-15T10:30:00Z",
  "tipoTransacao": "CREDITO",
  "tipoProdutoTransacao": "PIX",
  "nomeTitularConta": "John Doe",
  "dataNascimentoTitularConta": "1990-01-15T00:00:00Z",
  "zipCode": "12345-678"
}
```

## Project Structure

```
.
├── infrastructure/          # Terraform IaC
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── s3.tf
│   ├── dynamodb.tf
│   ├── opensearch.tf
│   └── glue.tf
├── glue-job/               # Scala Glue Job
│   ├── build.sbt
│   └── src/main/scala/
│       ├── FinancialTransactionProcessor.scala
│       ├── models/
│       ├── enrichment/
│       └── sink/
├── data-generation/        # Test data generators
│   ├── generate_transactions.py
│   ├── generate_customers.py
│   ├── requirements.txt
│   └── config.json
├── docs/                   # Documentation
│   ├── ARCHITECTURE.md
│   ├── DEPLOYMENT.md
│   └── DEMO.md
└── README.md
```

## Prerequisites

- AWS Account with appropriate permissions
- Terraform >= 1.0
- Python >= 3.8
- Scala 2.12
- SBT (Scala Build Tool)
- AWS CLI configured

## Quick Start

### 1. Deploy Infrastructure

```bash
cd infrastructure
terraform init
terraform plan
terraform apply
```

### 2. Generate Test Data

```bash
cd data-generation
pip install -r requirements.txt
python generate_customers.py
python generate_transactions.py
```

### 3. Build and Deploy Glue Job

```bash
cd glue-job
sbt clean package
# Upload JAR to S3 (output from terraform)
aws s3 cp target/scala-2.12/financial-transaction-processor_2.12-1.0.jar s3://YOUR_GLUE_SCRIPTS_BUCKET/
```

### 4. Run Glue Job

```bash
aws glue start-job-run --job-name financial-transaction-processor \
  --arguments='--year=2024,--month=01,--day=15'
```

## Technical Requirements Met

- ✅ S3 data in JSON format
- ✅ OpenSearch output in camelCase JSON
- ✅ Scala-based Glue Job
- ✅ MapPartitions for batch processing
- ✅ DynamoDB batch-get operations
- ✅ Infrastructure as Code (Terraform)
- ✅ Glue Job version 4.0
- ✅ 1000+ test records with 20+ distinct accounts

## Development Time Tracking

Track your development time and report during demo.

## Demo Checklist

- [ ] Infrastructure deployed successfully
- [ ] Test data generated and uploaded
- [ ] Glue Job executed without errors
- [ ] Data enriched correctly in OpenSearch
- [ ] Performance metrics reviewed
- [ ] Code walkthrough prepared

## License

This is a technical assessment project.
