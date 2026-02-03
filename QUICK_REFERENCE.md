# Guia de referência rápida

Este guia oferece acesso rápido aos comandos mais usados do pipeline de processamento em lote com AWS Glue.

## Verificação de pré-requisitos

```bash
# Verificar AWS CLI
aws --version

# Verificar Terraform
terraform --version

# Verificar Python
python3 --version

# Verificar Scala
scala -version

# Verificar SBT
sbt --version

# Verificar credenciais AWS
aws sts get-caller-identity
```

## Comandos de infraestrutura

### Terraform

```bash
# Navegar para o diretório de infraestrutura
cd infrastructure

# Inicializar Terraform
terraform init

# Validar configuração
terraform validate

# Formatar arquivos Terraform
terraform fmt

# Planejar implantação
terraform plan

# Aplicar infraestrutura
terraform apply

# Mostrar estado atual
terraform show

# Listar recursos
terraform state list

# Obter outputs
terraform output

# Destruir infraestrutura
terraform destroy
```

### Obter outputs específicos

```bash
# Nome do bucket S3
terraform output -raw s3_transactions_bucket

# Bucket de scripts do Glue
terraform output -raw glue_scripts_bucket

# Nome da tabela DynamoDB
terraform output -raw dynamodb_table_name

# Endpoint OpenSearch
terraform output -raw opensearch_endpoint

# Nome do job Glue
terraform output -raw glue_job_name
```

## Comandos de geração de dados

### Configuração

```bash
# Navegar para o diretório de geração de dados
cd data-generation

# Instalar dependências
pip install -r requirements.txt

# Ou com ambiente virtual
python3 -m venv venv
source venv/bin/activate  # No Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### Gerar dados

```bash
# Gerar dados de clientes
python generate_customers.py

# Gerar dados de transações
python generate_transactions.py

# Gerar ambos
python generate_customers.py && python generate_transactions.py
```

### Verificar dados

```bash
# Verificar DynamoDB
aws dynamodb scan --table-name customer-registration-dev --max-items 5

# Contar itens no DynamoDB
aws dynamodb scan --table-name customer-registration-dev --select COUNT

# Listar arquivos no S3
aws s3 ls s3://SEU-BUCKET/transactions/ --recursive

# Contar objetos no S3
aws s3 ls s3://SEU-BUCKET/transactions/ --recursive | wc -l

# Baixar arquivo de exemplo do S3
aws s3 cp s3://SEU-BUCKET/transactions/year=2024/month=01/day=15/transactions_xxx.json ./sample.json
```

## Comandos do job Glue

### Build

```bash
# Navegar para o diretório glue-job
cd glue-job

# Limpar builds anteriores
sbt clean

# Compilar
sbt compile

# Executar testes (se houver)
sbt test

# Empacotar JAR
sbt package

# Criar JAR assembly (fat JAR)
sbt assembly

# Verificar local do JAR
ls -lh target/scala-2.12/
```

### Implantar

```bash
# Definir variáveis
GLUE_BUCKET=$(cd ../infrastructure && terraform output -raw glue_scripts_bucket)
JAR_FILE="target/scala-2.12/financial-transaction-processor_2.12-1.0.jar"

# Enviar JAR para o S3
aws s3 cp $JAR_FILE s3://$GLUE_BUCKET/scripts/

# Verificar envio
aws s3 ls s3://$GLUE_BUCKET/scripts/

# Atualizar local do script do job Glue
JOB_NAME=$(cd ../infrastructure && terraform output -raw glue_job_name)
aws glue update-job --job-name $JOB_NAME \
  --job-update '{
    "Command": {
      "Name": "glueetl",
      "ScriptLocation": "s3://'$GLUE_BUCKET'/scripts/financial-transaction-processor_2.12-1.0.jar"
    }
  }'
```

### Executar

```bash
# Obter nome do job
JOB_NAME=$(cd infrastructure && terraform output -raw glue_job_name)

# Iniciar execução do job
aws glue start-job-run \
  --job-name $JOB_NAME \
  --arguments '{
    "--year":"2024",
    "--month":"01",
    "--day":"15"
  }'

# Iniciar com todos os parâmetros
aws glue start-job-run \
  --job-name $JOB_NAME \
  --arguments '{
    "--year":"2024",
    "--month":"01",
    "--day":"15",
    "--s3_bucket":"SEU-BUCKET",
    "--dynamodb_table":"customer-registration-dev",
    "--opensearch_endpoint":"SEU-ENDPOINT",
    "--opensearch_index":"financial-transactions",
    "--aws_region":"us-east-1"
  }'

# Obter ID da última execução
RUN_ID=$(aws glue get-job-runs --job-name $JOB_NAME --max-results 1 \
  --query 'JobRuns[0].Id' --output text)

echo "ID da execução: $RUN_ID"
```

### Monitorar

```bash
# Verificar status do job
aws glue get-job-run \
  --job-name $JOB_NAME \
  --run-id $RUN_ID \
  --query 'JobRun.JobRunState' \
  --output text

# Detalhes da execução
aws glue get-job-run \
  --job-name $JOB_NAME \
  --run-id $RUN_ID

# Listar todas as execuções
aws glue get-job-runs --job-name $JOB_NAME

# Acompanhar status (atualiza a cada 10 segundos)
watch -n 10 "aws glue get-job-run --job-name $JOB_NAME --run-id $RUN_ID \
  --query 'JobRun.JobRunState' --output text"
```

## Comandos CloudWatch Logs

```bash
# Listar grupos de log
aws logs describe-log-groups --log-group-name-prefix /aws-glue

# Acompanhar logs (modo follow)
aws logs tail /aws-glue/jobs/output --follow

# Logs desde um horário
aws logs tail /aws-glue/jobs/output --follow --since 30m

# Filtrar logs por erro
aws logs filter-log-events \
  --log-group-name /aws-glue/jobs/output \
  --filter-pattern "ERROR"

# Filtrar por execução específica
aws logs filter-log-events \
  --log-group-name /aws-glue/jobs/output \
  --filter-pattern "$RUN_ID"

# Eventos recentes
aws logs tail /aws-glue/jobs/output --since 1h
```

## Comandos OpenSearch

```bash
# Obter endpoint OpenSearch
OPENSEARCH_ENDPOINT=$(cd infrastructure && terraform output -raw opensearch_endpoint)

# Saúde do cluster
curl -X GET "https://$OPENSEARCH_ENDPOINT/_cluster/health?pretty"

# Listar índices
curl -X GET "https://$OPENSEARCH_ENDPOINT/_cat/indices?v"

# Contar documentos
curl -X GET "https://$OPENSEARCH_ENDPOINT/financial-transactions/_count?pretty"

# Buscar todos (limite 10)
curl -X GET "https://$OPENSEARCH_ENDPOINT/financial-transactions/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{"size": 10, "query": {"match_all": {}}}'

# Buscar por tipo de transação
curl -X GET "https://$OPENSEARCH_ENDPOINT/financial-transactions/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "term": {
        "tipoTransacao": "CREDITO"
      }
    }
  }'

# Agregação por tipo de transação
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

# Mapeamento do índice
curl -X GET "https://$OPENSEARCH_ENDPOINT/financial-transactions/_mapping?pretty"

# Excluir índice (cuidado!)
curl -X DELETE "https://$OPENSEARCH_ENDPOINT/financial-transactions"
```

## Comandos DynamoDB

```bash
# Obter nome da tabela
TABLE_NAME=$(cd infrastructure && terraform output -raw dynamodb_table_name)

# Descrever tabela
aws dynamodb describe-table --table-name $TABLE_NAME

# Scan (primeiros 10 itens)
aws dynamodb scan --table-name $TABLE_NAME --max-items 10

# Contar itens
aws dynamodb scan --table-name $TABLE_NAME --select COUNT

# Obter item específico
aws dynamodb get-item \
  --table-name $TABLE_NAME \
  --key '{"numero_unico_conta": {"S": "SEU-ACCOUNT-ID"}}'

# Batch get
aws dynamodb batch-get-item \
  --request-items '{
    "'$TABLE_NAME'": {
      "Keys": [
        {"numero_unico_conta": {"S": "ACCOUNT-ID-1"}},
        {"numero_unico_conta": {"S": "ACCOUNT-ID-2"}}
      ]
    }
  }'

# Query por partition key
aws dynamodb query \
  --table-name $TABLE_NAME \
  --key-condition-expression "numero_unico_conta = :account_id" \
  --expression-attribute-values '{":account_id": {"S": "SEU-ACCOUNT-ID"}}'
```

## Comandos S3

```bash
# Obter nome do bucket
BUCKET_NAME=$(cd infrastructure && terraform output -raw s3_transactions_bucket)

# Listar objetos
aws s3 ls s3://$BUCKET_NAME/transactions/ --recursive

# Listar partição específica
aws s3 ls s3://$BUCKET_NAME/transactions/year=2024/month=01/day=15/

# Copiar do S3
aws s3 cp s3://$BUCKET_NAME/transactions/year=2024/month=01/day=15/file.json ./

# Enviar para o S3
aws s3 cp local-file.json s3://$BUCKET_NAME/transactions/year=2024/month=01/day=15/

# Sincronizar diretório com S3
aws s3 sync ./local-dir s3://$BUCKET_NAME/transactions/

# Remover todos os objetos (cuidado!)
aws s3 rm s3://$BUCKET_NAME/transactions/ --recursive
```

## Comandos do Makefile

```bash
# Mostrar comandos disponíveis
make help

# Inicializar Terraform
make init

# Planejar alterações Terraform
make plan

# Aplicar infraestrutura
make apply

# Gerar dados de teste
make generate-data

# Compilar job Glue
make build-glue

# Implantar job Glue
make deploy-glue

# Executar job Glue
make run-glue

# Limpar artefatos de build
make clean

# Destruir infraestrutura
make destroy
```

## Comandos de troubleshooting

### Verificar recursos AWS

```bash
# Listar buckets S3
aws s3 ls

# Listar tabelas DynamoDB
aws dynamodb list-tables

# Listar domínios OpenSearch
aws opensearch list-domain-names

# Listar jobs Glue
aws glue list-jobs

# Verificar papel IAM
aws iam get-role --role-name glue-job-role
```

### Depurar job Glue

```bash
# Definição do job
aws glue get-job --job-name $JOB_NAME

# Erro da execução
aws glue get-job-run \
  --job-name $JOB_NAME \
  --run-id $RUN_ID \
  --query 'JobRun.ErrorMessage'

# Métricas CloudWatch
aws cloudwatch get-metric-statistics \
  --namespace Glue \
  --metric-name glue.driver.aggregate.numCompletedTasks \
  --dimensions Name=JobName,Value=$JOB_NAME Name=JobRunId,Value=$RUN_ID \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

### Comandos de limpeza

```bash
# Excluir todos os objetos do bucket S3
aws s3 rm s3://$BUCKET_NAME --recursive

# Excluir itens da tabela DynamoDB (scan e delete)
aws dynamodb scan --table-name $TABLE_NAME \
  --attributes-to-get numero_unico_conta \
  --query 'Items[*].numero_unico_conta.S' \
  --output text | xargs -I {} aws dynamodb delete-item \
  --table-name $TABLE_NAME \
  --key '{"numero_unico_conta": {"S": "{}"}}'

# Excluir índice OpenSearch
curl -X DELETE "https://$OPENSEARCH_ENDPOINT/financial-transactions"

# Parar job Glue em execução
aws glue batch-stop-job-run \
  --job-name $JOB_NAME \
  --job-run-ids $RUN_ID
```

## Variáveis de ambiente

```bash
# Definir variáveis comuns
export AWS_REGION=us-east-1
export AWS_PROFILE=default
export GLUE_JOB_NAME=$(cd infrastructure && terraform output -raw glue_job_name)
export S3_BUCKET=$(cd infrastructure && terraform output -raw s3_transactions_bucket)
export DYNAMODB_TABLE=$(cd infrastructure && terraform output -raw dynamodb_table_name)
export OPENSEARCH_ENDPOINT=$(cd infrastructure && terraform output -raw opensearch_endpoint)

# Salvar em .env
cat > .env << EOF
AWS_REGION=$AWS_REGION
GLUE_JOB_NAME=$GLUE_JOB_NAME
S3_BUCKET=$S3_BUCKET
DYNAMODB_TABLE=$DYNAMODB_TABLE
OPENSEARCH_ENDPOINT=$OPENSEARCH_ENDPOINT
EOF

# Carregar do .env
source .env
```

## One-liners úteis

```bash
# Pipeline completo de implantação
cd infrastructure && terraform apply -auto-approve && \
cd ../data-generation && python generate_customers.py && python generate_transactions.py && \
cd ../glue-job && sbt clean package && \
aws s3 cp target/scala-2.12/*.jar s3://$(cd ../infrastructure && terraform output -raw glue_scripts_bucket)/scripts/

# Executar job e acompanhar logs
aws glue start-job-run --job-name $JOB_NAME --arguments '{"--year":"2024","--month":"01","--day":"15"}' && \
aws logs tail /aws-glue/jobs/output --follow

# Verificar status do pipeline
echo "Arquivos S3: $(aws s3 ls s3://$S3_BUCKET/transactions/ --recursive | wc -l)" && \
echo "Itens DynamoDB: $(aws dynamodb scan --table-name $DYNAMODB_TABLE --select COUNT --query 'Count' --output text)" && \
echo "Docs OpenSearch: $(curl -s https://$OPENSEARCH_ENDPOINT/financial-transactions/_count | jq '.count')"
```

## Dicas e boas práticas

1. **Sempre verificar a região AWS**: Trabalhe na região correta
2. **Usar variáveis de ambiente**: Evite repetição de valores
3. **Monitorar custos**: Consulte o AWS Cost Explorer com frequência
4. **Limpar recursos**: Destrua a infraestrutura quando não estiver em uso
5. **Controle de versão**: Faça commits regularmente
6. **Testar incrementalmente**: Teste cada componente antes da integração
7. **Verificar logs**: Revise os logs do CloudWatch em caso de erro
8. **Backup de dados**: Mantenha cópias locais dos dados gerados
9. **Documentar mudanças**: Atualize a documentação ao alterar o código
10. **Usar o Makefile**: Use a automação para tarefas comuns

---

**Ajuda rápida**: Execute `make help` para ver os comandos de automação disponíveis
