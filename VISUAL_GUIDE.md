# 📊 Resumo Visual - Deploy e Execução do Job Scala

```
┌─────────────────────────────────────────────────────────────────────┐
│                     FLUXO COMPLETO DO PROJETO                       │
└─────────────────────────────────────────────────────────────────────┘

1️⃣  SETUP INICIAL (Uma vez)
   ┌──────────────────────────────────────────────────────┐
   │ aws configure                                        │
   │ ↓                                                    │
   │ Access Key: [SUA_ACCESS_KEY_AQUI]                   │
   │ Secret: [SUA_SECRET_KEY_AQUI]                       │
   │ Region: us-east-2                                    │
   └──────────────────────────────────────────────────────┘

2️⃣  DEPLOY INFRAESTRUTURA + SCALA (Automático)
   ┌──────────────────────────────────────────────────────┐
   │ ./deploy-full.sh                                     │
   │                                                      │
   │ Este script faz:                                     │
   │ ✓ terraform init && terraform apply                 │
   │ ✓ sbt clean assembly                                │
   │ ✓ aws s3 cp jar s3://bucket/scripts/                │
   │ ✓ aws glue update-job                               │
   └──────────────────────────────────────────────────────┘
               ↓
   ┌──────────────────────────────────────────────────────┐
   │ RECURSOS CRIADOS (32 total):                         │
   │                                                      │
   │ 📦 S3 Buckets (2):                                   │
   │    • financial-transactions-dev-160885283918         │
   │    • glue-scripts-dev-160885283918                   │
   │                                                      │
   │ 🗄️  DynamoDB (1):                                    │
   │    • customer-registration-dev                       │
   │                                                      │
   │ 🔍 OpenSearch (1):                                   │
   │    • financial-txns-dev                              │
   │                                                      │
   │ ⚙️  Glue Job (1):                                     │
   │    • financial-transaction-processor                 │
   │                                                      │
   │ 🔐 IAM Roles + Policies                              │
   │ 📊 CloudWatch Logs + Alarms                          │
   └──────────────────────────────────────────────────────┘

3️⃣  GERAR DADOS DE TESTE
   ┌──────────────────────────────────────────────────────┐
   │ make generate-data                                   │
   │                                                      │
   │ Cria:                                                │
   │ • Clientes no DynamoDB                               │
   │ • Transações no S3                                   │
   └──────────────────────────────────────────────────────┘

4️⃣  EXECUTAR JOB SCALA
   ┌──────────────────────────────────────────────────────┐
   │ make run-glue                                        │
   │                                                      │
   │ Ou manualmente:                                      │
   │ aws glue start-job-run \                             │
   │   --job-name financial-transaction-processor \       │
   │   --arguments '{                                     │
   │     "--year":"2024",                                 │
   │     "--month":"02",                                  │
   │     "--day":"04"                                     │
   │   }'                                                 │
   └──────────────────────────────────────────────────────┘
               ↓
   ┌──────────────────────────────────────────────────────┐
   │ O QUE O JOB FAZ:                                     │
   │                                                      │
   │ S3 (JSON)                                            │
   │    ↓ [Lê transações particionadas]                  │
   │ Spark/Glue                                           │
   │    ↓ [MapPartitions - batch processing]             │
   │ DynamoDB                                             │
   │    ↓ [BatchGetItem - max 100/request]               │
   │ Enriquecimento                                       │
   │    ↓ [Merge transação + cliente]                    │
   │ OpenSearch                                           │
   │    ✓ [Bulk index - camelCase]                       │
   └──────────────────────────────────────────────────────┘

5️⃣  MONITORAR
   ┌──────────────────────────────────────────────────────┐
   │ aws logs tail /aws-glue/jobs/... --follow           │
   │                                                      │
   │ Ou via Console:                                      │
   │ https://us-east-2.console.aws.amazon.com/glue       │
   └──────────────────────────────────────────────────────┘

6️⃣  VERIFICAR RESULTADOS
   ┌──────────────────────────────────────────────────────┐
   │ OpenSearch Dashboard:                                │
   │ https://<endpoint>/_dashboards                       │
   │                                                      │
   │ Índice: financial-transactions                       │
   └──────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                    QUANDO O JOB É EXECUTADO?                        │
└─────────────────────────────────────────────────────────────────────┘

📅 ATUALMENTE: Manual
   • Você decide quando executar
   • make run-glue
   • aws glue start-job-run

📅 FUTURO (Configurável): Automático

   Opção 1: Agendamento (Cron)
   ┌──────────────────────────────────────────┐
   │ Todos os dias às 2h da manhã             │
   │ cron(0 2 * * ? *)                        │
   │                                          │
   │ Adicionar ao Terraform:                  │
   │ resource "aws_glue_trigger" {...}        │
   └──────────────────────────────────────────┘

   Opção 2: Evento S3
   ┌──────────────────────────────────────────┐
   │ Quando novos arquivos chegam no S3       │
   │ Trigger automático                       │
   └──────────────────────────────────────────┘

   Opção 3: EventBridge
   ┌──────────────────────────────────────────┐
   │ Regras customizadas                      │
   │ Dias da semana, horários específicos     │
   └──────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                      LOCALIZAÇÃO DO CÓDIGO                          │
└─────────────────────────────────────────────────────────────────────┘

📁 glue-job/
   ├── src/main/scala/
   │   ├── FinancialTransactionProcessor.scala  ← Main job
   │   ├── enrichment/
   │   │   └── DynamoDBEnricher.scala           ← DynamoDB logic
   │   ├── models/
   │   │   └── Transaction.scala                ← Data models
   │   └── sink/
   │       └── OpenSearchSink.scala             ← OpenSearch write
   ├── build.sbt                                ← Dependencies
   └── target/scala-2.12/
       └── financial-transaction-processor-assembly-1.0.jar  ← Compiled

📍 LOCALIZAÇÃO NO S3 (após deploy):
   s3://glue-scripts-dev-160885283918/scripts/
      └── financial-transaction-processor-assembly-1.0.jar

📍 AWS GLUE JOB aponta para:
   ScriptLocation: s3://glue-scripts-dev-160885283918/scripts/*.jar

┌─────────────────────────────────────────────────────────────────────┐
│                     COMANDOS MAIS USADOS                            │
└─────────────────────────────────────────────────────────────────────┘

# Deploy completo (primeira vez)
./deploy-full.sh

# Gerar dados
make generate-data

# Executar job
make run-glue

# Ver logs
aws logs tail /aws-glue/jobs/financial-transaction-processor --follow

# Status das execuções
aws glue get-job-runs --job-name financial-transaction-processor

# Re-compilar e fazer deploy (após mudanças no código)
make deploy-glue

# Destruir tudo
make destroy

┌─────────────────────────────────────────────────────────────────────┐
│                      CUSTOS ESTIMADOS                               │
└─────────────────────────────────────────────────────────────────────┘

💰 Por Mês (ambiente dev):
   • OpenSearch t3.small: ~$35-40
   • S3: ~$0.50 (armazenamento inicial)
   • DynamoDB: ~$0 (on-demand, sem tráfego)
   • CloudWatch Logs: ~$1

💰 Por Execução do Job:
   • Glue G.1X (2 workers): $0.44/hora
   • Exemplo: Job de 10 min = ~$0.15

📊 TOTAL: ~$40-50/mês (com execuções ocasionais)

┌─────────────────────────────────────────────────────────────────────┐
│                         PRÓXIMOS PASSOS                             │
└─────────────────────────────────────────────────────────────────────┘

1. Executar deploy completo:
   ./deploy-full.sh

2. Aguardar ~15 minutos (criação do OpenSearch)

3. Gerar dados de teste:
   make generate-data

4. Executar o job:
   make run-glue

5. Monitorar e verificar resultados

6. Quando terminar os testes:
   make destroy
```
