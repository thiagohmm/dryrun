# ❓ Perguntas Frequentes - Job Scala no AWS Glue

## 1. Onde fica o código Scala?

**Localização Local:**

```
/home/thiagohmm/Estudo/dryRun/glue-job/src/main/scala/
├── FinancialTransactionProcessor.scala  ← Código principal
├── enrichment/
│   └── DynamoDBEnricher.scala           ← Lógica de enriquecimento
├── models/
│   └── Transaction.scala                ← Modelos de dados
└── sink/
    └── OpenSearchSink.scala             ← Gravação no OpenSearch
```

**Após Compilação:**

```
/home/thiagohmm/Estudo/dryRun/glue-job/target/scala-2.12/
└── financial-transaction-processor-assembly-1.0.jar
```

**No S3 (após deploy):**

```
s3://glue-scripts-dev-160885283918/scripts/financial-transaction-processor-assembly-1.0.jar
```

---

## 2. Como o script Scala vai para o AWS Glue?

### Processo Completo:

```
1. COMPILAÇÃO (local)
   cd glue-job
   sbt clean assembly
   ↓
   Gera JAR: target/scala-2.12/financial-transaction-processor-assembly-1.0.jar

2. UPLOAD PARA S3
   aws s3 cp target/scala-2.12/*.jar s3://glue-scripts-dev-160885283918/scripts/
   ↓
   JAR agora está no S3

3. CONFIGURAÇÃO DO JOB GLUE
   aws glue update-job --job-name financial-transaction-processor \
     --job-update '{"Command": {"ScriptLocation": "s3://bucket/scripts/jar"}}'
   ↓
   Job Glue aponta para o JAR no S3

4. EXECUÇÃO
   aws glue start-job-run --job-name financial-transaction-processor
   ↓
   Glue baixa o JAR do S3 e executa
```

### Automático (usando o script):

```bash
./deploy-full.sh
# Faz TUDO automaticamente!
```

---

## 3. Quando o job Scala será executado?

### 📅 ATUALMENTE: MANUAL

O job **NÃO executa automaticamente**. Você precisa disparar manualmente:

**Opção 1 - Via Makefile:**

```bash
make run-glue
```

**Opção 2 - Via AWS CLI:**

```bash
aws glue start-job-run \
  --job-name financial-transaction-processor \
  --arguments '{
    "--year":"2024",
    "--month":"02",
    "--day":"04"
  }'
```

**Opção 3 - Via Console AWS:**

1. Acesse: https://us-east-2.console.aws.amazon.com/glue
2. Vá em **ETL Jobs** → **Jobs**
3. Selecione `financial-transaction-processor`
4. Clique em **Run**

### 📅 FUTURO: AUTOMÁTICO (Requer configuração)

Para executar automaticamente, você precisa adicionar um **Trigger** no Terraform:

#### A) Agendamento Diário (Cron)

Adicione ao `infrastructure/glue.tf`:

```hcl
resource "aws_glue_trigger" "daily_schedule" {
  name     = "financial-processor-daily-trigger"
  type     = "SCHEDULED"
  schedule = "cron(0 2 * * ? *)"  # Todo dia às 2h AM UTC

  actions {
    job_name = aws_glue_job.financial_transaction_processor.name
    arguments = {
      "--year"  = "{{year}}"   # Variável dinâmica
      "--month" = "{{month}}"
      "--day"   = "{{day}}"
    }
  }
}
```

Depois execute:

```bash
cd infrastructure
terraform apply
```

Agora o job executará **automaticamente todo dia às 2h da manhã**.

#### B) Quando Novos Dados Chegam (Event-Driven)

```hcl
resource "aws_glue_trigger" "on_new_data" {
  name = "financial-processor-on-new-file"
  type = "CONDITIONAL"

  actions {
    job_name = aws_glue_job.financial_transaction_processor.name
  }

  predicate {
    conditions {
      crawler_name = aws_glue_crawler.transactions.name
      crawl_state  = "SUCCEEDED"
    }
  }
}
```

O job executará **automaticamente quando o Crawler detectar novos arquivos**.

#### C) Múltiplos Horários (EventBridge)

```hcl
# Executar às 6h, 12h e 18h
resource "aws_cloudwatch_event_rule" "three_times_daily" {
  name                = "financial-processor-3x-daily"
  schedule_expression = "cron(0 6,12,18 * * ? *)"
}

resource "aws_cloudwatch_event_target" "glue" {
  rule     = aws_cloudwatch_event_rule.three_times_daily.name
  arn      = aws_glue_job.financial_transaction_processor.arn
  role_arn = aws_iam_role.eventbridge_glue.arn
}
```

---

## 4. Como sei que o job está rodando?

### Ver Status em Tempo Real:

```bash
# Listar todas as execuções
aws glue get-job-runs --job-name financial-transaction-processor

# Ver apenas a última execução
aws glue get-job-runs \
  --job-name financial-transaction-processor \
  --max-results 1
```

**Saída exemplo:**

```json
{
  "JobRunId": "jr_abc123",
  "JobRunState": "RUNNING",  ← Status: RUNNING, SUCCEEDED, FAILED
  "StartedOn": "2024-02-04T10:30:00Z",
  "ExecutionTime": 120,      ← Segundos
  "DPUSeconds": 240.5
}
```

### Ver Logs em Tempo Real:

```bash
aws logs tail /aws-glue/jobs/financial-transaction-processor --follow
```

### Via Console:

```
https://us-east-2.console.aws.amazon.com/glue/home?region=us-east-2#/v2/etl-configuration/jobs/view/financial-transaction-processor
```

---

## 5. Posso modificar o código Scala depois?

**SIM!** É muito simples:

### Passos:

```bash
# 1. Edite o código
vim glue-job/src/main/scala/FinancialTransactionProcessor.scala

# 2. Recompile
cd glue-job
sbt clean assembly

# 3. Faça re-deploy
cd ..
make deploy-glue

# Pronto! Próxima execução usará o novo código
```

**Ou tudo de uma vez:**

```bash
make deploy-glue  # Compila + Upload + Atualiza job
```

---

## 6. O que acontece se o job falhar?

### Retry Automático

O job está configurado com **max_retries = 1** no Terraform.

Se falhar, tentará **1 vez** automaticamente.

### Alarmes CloudWatch

Um alarme será disparado quando:

- Job falhar
- Timeout (60 minutos)
- Erros no processamento

### Ver Causa da Falha:

```bash
# Ver logs de erro
aws logs tail /aws-glue/jobs/financial-transaction-processor \
  --filter-pattern ERROR

# Ou ver detalhes do job run
aws glue get-job-run \
  --job-name financial-transaction-processor \
  --run-id jr_<ID>
```

---

## 7. Quanto custa executar o job?

### Preços AWS Glue (região us-east-2):

**Worker G.1X:**

- $0.44 por DPU-hora
- 2 workers = 2 DPUs

**Exemplo de custo:**

| Duração | DPU-hora | Custo |
| ------- | -------- | ----- |
| 5 min   | 0.167    | $0.07 |
| 10 min  | 0.333    | $0.15 |
| 30 min  | 1.0      | $0.44 |
| 60 min  | 2.0      | $0.88 |

**Execuções mensais:**

- 1x/dia: ~30 execuções × $0.15 = **$4.50/mês**
- 3x/dia: ~90 execuções × $0.15 = **$13.50/mês**

---

## 8. Como testar localmente antes de fazer deploy?

### Opção 1: Unit Tests (Scala)

```bash
cd glue-job
sbt test
```

### Opção 2: Spark Local

```bash
# Adicione ao código
spark.master("local[*]")  # Para testes locais

# Execute
sbt "runMain FinancialTransactionProcessor ..."
```

### Opção 3: AWS Glue Dev Endpoint (Notebook)

Crie um endpoint de desenvolvimento no AWS Glue Console e teste interativamente.

---

## 9. Preciso recriar a infraestrutura quando atualizo o código?

**NÃO!**

- **Código Scala**: Apenas recompile e faça upload (`make deploy-glue`)
- **Configurações Terraform**: Apenas `terraform apply`
- **Infraestrutura total**: Apenas se mudar recursos (S3, DynamoDB, etc.)

### Matriz de Mudanças:

| Mudança             | Comando            | Recreia?    |
| ------------------- | ------------------ | ----------- |
| Código Scala        | `make deploy-glue` | ❌          |
| Configuração Job    | `terraform apply`  | ❌          |
| Worker type/count   | `terraform apply`  | ✅ (Job)    |
| Adicionar S3 bucket | `terraform apply`  | ✅ (Bucket) |
| Destruir tudo       | `make destroy`     | ✅ (Tudo)   |

---

## 10. Como debugar problemas?

### Checklist:

1. **JAR está no S3?**

   ```bash
   aws s3 ls s3://glue-scripts-dev-160885283918/scripts/
   ```

2. **Job aponta para o JAR correto?**

   ```bash
   aws glue get-job --job-name financial-transaction-processor \
     | grep ScriptLocation
   ```

3. **Permissões IAM corretas?**

   ```bash
   aws iam get-role --role-name financial-batch-processor-glue-job-role-dev
   ```

4. **Dados existem no S3?**

   ```bash
   aws s3 ls s3://financial-transactions-dev-160885283918/transactions/
   ```

5. **DynamoDB tem dados?**

   ```bash
   aws dynamodb scan --table-name customer-registration-dev --limit 5
   ```

6. **Logs de erro?**
   ```bash
   aws logs tail /aws-glue/jobs/financial-transaction-processor \
     --since 1h --filter-pattern ERROR
   ```

---

## 📚 Documentos Relacionados

- [SCALA_DEPLOYMENT.md](./SCALA_DEPLOYMENT.md) - Deploy detalhado
- [JOB_EXECUTION.md](./JOB_EXECUTION.md) - Guia de execução
- [VISUAL_GUIDE.md](./VISUAL_GUIDE.md) - Guia visual
- [SETUP_AWS.md](./SETUP_AWS.md) - Setup AWS
