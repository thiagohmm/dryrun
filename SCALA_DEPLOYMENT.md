# 🚀 Guia Completo - Deploy e Execução do Job Scala no AWS Glue

## 📦 Sobre o Job Scala

O job `FinancialTransactionProcessor.scala` é responsável por:

1. **Ler** transações do S3 (particionadas por ano/mês/dia)
2. **Enriquecer** com dados de clientes do DynamoDB (batch-get eficiente)
3. **Gravar** dados enriquecidos no OpenSearch

### Características Técnicas:

- Processamento em lote com MapPartitions
- Batch-get no DynamoDB (max 100 itens/request)
- Indexação em massa no OpenSearch
- Tratamento de erros e retry

---

## 🔨 Passo 1: Compilar o Job Scala

### 1.1 Verificar se SBT está instalado:

```bash
sbt --version
```

Se não estiver instalado, instale:

```bash
# Ubuntu/Debian
echo "deb https://repo.scala-sbt.org/scalasbt/debian all main" | sudo tee /etc/apt/sources.list.d/sbt.list
curl -sL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x2EE0EA64E40A89B84B2DF73499E82A75642AC823" | sudo apt-key add
sudo apt-get update
sudo apt-get install sbt
```

### 1.2 Compilar e criar o JAR:

```bash
cd /home/thiagohmm/Estudo/dryRun/glue-job
sbt clean assembly
```

**Saída esperada:**

```
[info] Built: /home/thiagohmm/Estudo/dryRun/glue-job/target/scala-2.12/financial-transaction-processor-assembly-1.0.jar
```

Ou use o Makefile:

```bash
cd /home/thiagohmm/Estudo/dryRun
make build-glue
```

---

## 📤 Passo 2: Fazer Deploy do JAR para S3

### 2.1 Após aplicar o Terraform, obter o nome do bucket:

```bash
cd /home/thiagohmm/Estudo/dryRun/infrastructure
terraform output glue_scripts_bucket
```

### 2.2 Fazer upload do JAR para o S3:

```bash
BUCKET=$(cd infrastructure && terraform output -raw glue_scripts_bucket)
aws s3 cp glue-job/target/scala-2.12/financial-transaction-processor-assembly-1.0.jar \
  s3://$BUCKET/scripts/financial-transaction-processor-assembly-1.0.jar
```

Ou use o Makefile (compila e faz deploy automaticamente):

```bash
make deploy-glue
```

### 2.3 Verificar o upload:

```bash
aws s3 ls s3://glue-scripts-dev-160885283918/scripts/
```

---

## 🔧 Passo 3: Atualizar o Job Glue com o Script Correto

Após fazer o upload do JAR, você precisa atualizar o job Glue para apontar para o script correto.

### Opção 1: Via Terraform (Recomendado)

Atualize o arquivo `infrastructure/glue.tf`:

```hcl
# Na linha do script_location, altere de:
script_location = "s3://${aws_s3_bucket.glue_scripts.id}/scripts/placeholder.scala"

# Para:
script_location = "s3://${aws_s3_bucket.glue_scripts.id}/scripts/financial-transaction-processor-assembly-1.0.jar"
```

E aplique novamente:

```bash
cd infrastructure
terraform apply
```

### Opção 2: Via AWS CLI

```bash
aws glue update-job \
  --job-name financial-transaction-processor \
  --job-update '{
    "Command": {
      "Name": "glueetl",
      "ScriptLocation": "s3://glue-scripts-dev-160885283918/scripts/financial-transaction-processor-assembly-1.0.jar"
    }
  }'
```

---

## ▶️ Passo 4: Executar o Job

### 4.1 Executar via AWS CLI:

```bash
aws glue start-job-run \
  --job-name financial-transaction-processor \
  --arguments '{
    "--year":"2024",
    "--month":"01",
    "--day":"15",
    "--s3_bucket":"financial-transactions-dev-160885283918",
    "--dynamodb_table":"customer-registration-dev",
    "--opensearch_endpoint":"<ENDPOINT_DO_TERRAFORM_OUTPUT>",
    "--opensearch_index":"financial-transactions",
    "--aws_region":"us-east-2"
  }'
```

### 4.2 Executar via Makefile (simplificado):

```bash
make run-glue
```

### 4.3 Verificar status da execução:

```bash
# Listar execuções do job
aws glue get-job-runs --job-name financial-transaction-processor

# Ver detalhes de uma execução específica
aws glue get-job-run \
  --job-name financial-transaction-processor \
  --run-id <JOB_RUN_ID>
```

---

## 📊 Passo 5: Monitorar a Execução

### 5.1 Via CloudWatch Logs:

```bash
# Listar log streams
aws logs describe-log-streams \
  --log-group-name /aws-glue/jobs/financial-transaction-processor \
  --order-by LastEventTime \
  --descending

# Ver logs (substitua pelo stream name)
aws logs get-log-events \
  --log-group-name /aws-glue/jobs/financial-transaction-processor \
  --log-stream-name <STREAM_NAME>
```

### 5.2 Via Console AWS:

1. Acesse: https://us-east-2.console.aws.amazon.com/glue/
2. Menu lateral: **ETL Jobs** → **Jobs**
3. Clique em `financial-transaction-processor`
4. Aba **Run history** → Veja execuções
5. Clique em uma execução → **CloudWatch logs**

---

## 🔄 Quando o Job será Executado?

### Execução Manual (Atual):

- Via AWS CLI com `start-job-run`
- Via Console AWS Glue
- Via Makefile: `make run-glue`

### Execução Agendada (Futuro):

Para agendar execuções automáticas, você pode:

#### Opção 1: AWS Glue Triggers (Terraform)

Adicione ao `infrastructure/glue.tf`:

```hcl
# Trigger diário às 2h da manhã
resource "aws_glue_trigger" "daily_schedule" {
  name     = "financial-processor-daily"
  type     = "SCHEDULED"
  schedule = "cron(0 2 * * ? *)"  # 2h AM UTC todos os dias

  actions {
    job_name = aws_glue_job.financial_transaction_processor.name
    arguments = {
      "--year"               = "{{year}}"
      "--month"              = "{{month}}"
      "--day"                = "{{day}}"
      "--s3_bucket"          = aws_s3_bucket.transactions.id
      "--dynamodb_table"     = aws_dynamodb_table.customer_registration.name
      "--opensearch_endpoint" = aws_opensearch_domain.financial_transactions.endpoint
      "--opensearch_index"   = "financial-transactions"
      "--aws_region"         = var.aws_region
    }
  }
}
```

#### Opção 2: EventBridge (mais flexível)

```hcl
resource "aws_cloudwatch_event_rule" "daily_processing" {
  name                = "financial-processor-daily"
  description         = "Trigger Glue job daily"
  schedule_expression = "cron(0 2 * * ? *)"
}

resource "aws_cloudwatch_event_target" "glue_job" {
  rule     = aws_cloudwatch_event_rule.daily_processing.name
  arn      = aws_glue_job.financial_transaction_processor.arn
  role_arn = aws_iam_role.eventbridge_glue.arn

  input = jsonencode({
    "--year"               = "{{year}}"
    "--month"              = "{{month}}"
    "--day"                = "{{day}}"
    "--s3_bucket"          = "financial-transactions-dev-160885283918"
    "--dynamodb_table"     = "customer-registration-dev"
    "--opensearch_endpoint" = "<endpoint>"
    "--opensearch_index"   = "financial-transactions"
    "--aws_region"         = "us-east-2"
  })
}
```

#### Opção 3: Trigger baseado em evento S3

Executar automaticamente quando novos arquivos chegam no S3:

```hcl
resource "aws_glue_trigger" "on_s3_event" {
  name = "financial-processor-on-new-file"
  type = "EVENT"

  actions {
    job_name = aws_glue_job.financial_transaction_processor.name
  }

  event_batching_condition {
    batch_size   = 1
    batch_window = 900  # 15 minutos
  }

  predicate {
    conditions {
      crawler_name = aws_glue_crawler.transactions.name
      crawl_state  = "SUCCEEDED"
    }
  }
}
```

---

## 🎯 Resumo do Fluxo Completo

```
1. Compilar Scala
   ↓
   sbt clean assembly
   ↓
2. Deploy JAR para S3
   ↓
   aws s3 cp target/.../jar s3://bucket/scripts/
   ↓
3. Atualizar Job Glue (se necessário)
   ↓
   terraform apply ou aws glue update-job
   ↓
4. Executar Job
   ↓
   aws glue start-job-run ou make run-glue
   ↓
5. Monitorar
   ↓
   CloudWatch Logs
```

---

## 📝 Comandos Rápidos

```bash
# Build completo
cd /home/thiagohmm/Estudo/dryRun
make build-glue

# Deploy para S3
make deploy-glue

# Executar job
make run-glue

# Ver outputs importantes
cd infrastructure
terraform output opensearch_endpoint
terraform output glue_scripts_bucket
terraform output s3_transactions_bucket
```

---

## ⚠️ Importante

1. **Primeiro aplique o Terraform** (`make apply`) para criar a infraestrutura
2. **Depois compile e faça deploy** do JAR Scala (`make deploy-glue`)
3. **Atualize o job** para apontar para o JAR correto
4. **Execute o job** quando quiser processar dados (`make run-glue`)

Quer que eu atualize o arquivo Terraform para apontar diretamente para o JAR correto? 🤔
