# 🎯 Execução do Job Scala - Guia Rápido

## ✅ Pré-requisitos

Antes de executar o job Scala, certifique-se de que:

1. ✅ AWS CLI configurado (`aws configure`)
2. ✅ Credenciais AWS válidas (testado com `aws sts get-caller-identity`)
3. ✅ Infraestrutura Terraform aplicada (`terraform apply`)
4. ✅ JAR Scala compilado e uploaded para S3

---

## 🚀 Deploy Completo (Primeira Vez)

### Opção 1: Script Automatizado (Recomendado)

```bash
cd /home/thiagohmm/Estudo/dryRun
./deploy-full.sh
```

Este script faz **TUDO**:

- ✅ Aplica infraestrutura Terraform
- ✅ Compila o job Scala (sbt assembly)
- ✅ Faz upload do JAR para S3
- ✅ Atualiza o job Glue
- ✅ Cria arquivo de configuração

### Opção 2: Passo a Passo Manual

```bash
# 1. Aplicar infraestrutura
cd /home/thiagohmm/Estudo/dryRun/infrastructure
terraform init
terraform apply

# 2. Compilar Scala
cd /home/thiagohmm/Estudo/dryRun/glue-job
sbt clean assembly

# 3. Upload do JAR
BUCKET=$(cd ../infrastructure && terraform output -raw glue_scripts_bucket)
JAR_FILE=$(find target/scala-2.12 -name "*assembly*.jar" | head -1)
aws s3 cp "$JAR_FILE" "s3://$BUCKET/scripts/"

# 4. Atualizar job Glue
JOB_NAME=$(cd ../infrastructure && terraform output -raw glue_job_name)
JAR_NAME=$(basename "$JAR_FILE")
aws glue update-job \
  --job-name "$JOB_NAME" \
  --job-update "{\"Command\": {\"Name\": \"glueetl\", \"ScriptLocation\": \"s3://$BUCKET/scripts/$JAR_NAME\", \"PythonVersion\": \"3\"}}"
```

---

## ▶️ Executar o Job

### Via Makefile (Mais Fácil)

```bash
cd /home/thiagohmm/Estudo/dryRun
make run-glue
```

### Via AWS CLI (Controle Total)

```bash
# Obter configurações
source job-config.env

# Executar job
aws glue start-job-run \
  --job-name "$JOB_NAME" \
  --arguments '{
    "--year":"2024",
    "--month":"01",
    "--day":"15",
    "--s3_bucket":"'$S3_BUCKET'",
    "--dynamodb_table":"'$DYNAMODB_TABLE'",
    "--opensearch_endpoint":"'$OPENSEARCH_ENDPOINT'",
    "--opensearch_index":"'$OPENSEARCH_INDEX'",
    "--aws_region":"'$AWS_REGION'"
  }'
```

### Executar para data específica

```bash
aws glue start-job-run \
  --job-name financial-transaction-processor \
  --arguments '{
    "--year":"2024",
    "--month":"02",
    "--day":"04"
  }'
```

---

## 📊 Monitorar Execução

### Ver status da execução

```bash
# Listar todas as execuções
aws glue get-job-runs --job-name financial-transaction-processor

# Ver detalhes da última execução
aws glue get-job-runs \
  --job-name financial-transaction-processor \
  --max-results 1
```

### Ver logs em tempo real

```bash
# Tail dos logs
aws logs tail /aws-glue/jobs/financial-transaction-processor --follow

# Ver últimos logs
aws logs tail /aws-glue/jobs/financial-transaction-processor --since 10m
```

### Via Console AWS

```
https://us-east-2.console.aws.amazon.com/glue/home?region=us-east-2#/v2/etl-configuration/jobs
```

---

## 🔄 Quando o Job é Executado?

### Atualmente: Execução Manual

O job só executa quando você dispara manualmente via:

- AWS CLI: `aws glue start-job-run`
- Console AWS: botão "Run job"
- Makefile: `make run-glue`

### Futuro: Execução Automática (Opções)

#### 1. **Agendamento Diário** (cron)

Adicione ao Terraform (`infrastructure/glue.tf`):

```hcl
resource "aws_glue_trigger" "daily_schedule" {
  name     = "financial-processor-daily"
  type     = "SCHEDULED"
  schedule = "cron(0 2 * * ? *)"  # 2h AM UTC

  actions {
    job_name = aws_glue_job.financial_transaction_processor.name
  }
}
```

Aplique: `terraform apply`

#### 2. **Trigger por Evento S3** (novos arquivos)

Executa automaticamente quando novos dados chegam no S3:

```hcl
resource "aws_glue_trigger" "on_new_file" {
  name = "financial-processor-on-file"
  type = "EVENT"

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

#### 3. **EventBridge** (mais flexível)

Crie regras customizadas no EventBridge para diferentes horários, dias da semana, etc.

---

## 🔧 Atualizar o Job

### Quando modificar o código Scala:

```bash
# 1. Recompilar
cd /home/thiagohmm/Estudo/dryRun/glue-job
sbt clean assembly

# 2. Re-deploy
cd /home/thiagohmm/Estudo/dryRun
make deploy-glue

# Pronto! Próxima execução usará o novo código
```

### Quando modificar configurações Terraform:

```bash
cd /home/thiagohmm/Estudo/dryRun/infrastructure
terraform apply
```

---

## 📝 Comandos Úteis

```bash
# Ver todos os comandos disponíveis
make help

# Ver outputs do Terraform
cd infrastructure
terraform output

# Ver buckets S3
aws s3 ls

# Ver tabelas DynamoDB
aws dynamodb list-tables

# Ver domínios OpenSearch
aws opensearch list-domain-names

# Ver jobs Glue
aws glue list-jobs

# Cancelar execução em andamento
aws glue batch-stop-job-run \
  --job-name financial-transaction-processor \
  --job-run-ids jr_<ID>
```

---

## 🎯 Fluxo Típico de Trabalho

```
1. Primeira vez (setup):
   ./deploy-full.sh
   ↓
2. Gerar dados de teste:
   make generate-data
   ↓
3. Executar job:
   make run-glue
   ↓
4. Monitorar:
   aws logs tail /aws-glue/jobs/financial-transaction-processor --follow
   ↓
5. Verificar resultados:
   - OpenSearch Dashboard
   - CloudWatch Metrics
```

---

## ⚠️ Importante

- **Custos**: O job Glue cobra por DPU-hora. Worker G.1X = $0.44/hora
- **Timeout**: Configurado para 60 minutos
- **Concorrência**: Apenas 1 execução por vez (configurável)
- **Dados**: Certifique-se de ter dados no S3 antes de executar

---

## 🆘 Troubleshooting

### Job falha imediatamente

- Verifique se o JAR está no S3: `aws s3 ls s3://glue-scripts-dev-160885283918/scripts/`
- Verifique logs: `aws logs tail /aws-glue/jobs/financial-transaction-processor`

### Permissões negadas

- Verifique IAM role do Glue tem permissões para S3, DynamoDB e OpenSearch
- Re-aplique Terraform: `terraform apply`

### Dados não aparecem no OpenSearch

- Verifique se OpenSearch está acessível
- Teste endpoint: `curl https://<endpoint>/_cat/indices`
- Veja logs do job para erros de conexão

---

## 📚 Documentação Adicional

- [SCALA_DEPLOYMENT.md](./SCALA_DEPLOYMENT.md) - Guia completo de deployment
- [SETUP_AWS.md](./SETUP_AWS.md) - Configuração AWS
- [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) - Arquitetura detalhada
- [docs/DEMO.md](./docs/DEMO.md) - Demonstração passo a passo
