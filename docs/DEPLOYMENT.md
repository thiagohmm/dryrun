# Guia de implantação

Este guia traz instruções passo a passo para implantar o pipeline de processamento em lote com AWS Glue.

## Pré-requisitos

### Ferramentas necessárias

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

4. **Scala e SBT**
   ```bash
   scala -version
   # Scala code runner version 2.12.x
   sbt --version
   # sbt version 1.x.x
   ```

### Configuração da conta AWS

1. **Configurar credenciais AWS**

   ```bash
   aws configure
   # AWS Access Key ID: SUA_ACCESS_KEY
   # AWS Secret Access Key: SUA_SECRET_KEY
   # Default region name: us-east-1
   # Default output format: json
   ```

2. **Verificar permissões**
   Permissões IAM necessárias:
   - S3: Acesso total
   - DynamoDB: Acesso total
   - OpenSearch: Acesso total
   - Glue: Acesso total
   - IAM: Criar papéis e políticas
   - CloudWatch: Logs e métricas

## Passos de implantação

### Passo 1: Clonar e configurar o projeto

```bash
# Navegar para o diretório do projeto
cd /caminho/para/dryRun

# Verificar estrutura
ls -la
```

### Passo 2: Configurar variáveis do Terraform

```bash
cd infrastructure

# Criar terraform.tfvars a partir do exemplo
cp terraform.tfvars.example terraform.tfvars

# Editar variáveis
nano terraform.tfvars
```

**Exemplo de terraform.tfvars**:

```hcl
aws_region = "us-east-1"
project_name = "financial-batch-processor"
environment = "dev"

# Configuração S3
s3_bucket_name = "financial-transactions-dev-12345"

# Configuração DynamoDB
dynamodb_table_name = "customer-registration-dev"
dynamodb_billing_mode = "PAY_PER_REQUEST"

# Configuração OpenSearch
opensearch_domain_name = "financial-txns-dev"
opensearch_instance_type = "t3.small.search"
opensearch_instance_count = 1
opensearch_ebs_volume_size = 10

# Configuração Glue
glue_job_name = "financial-transaction-processor"
glue_worker_type = "G.1X"
glue_number_of_workers = 2
glue_max_retries = 1

# Rede (opcional - implantação em VPC)
# vpc_id = "vpc-xxxxx"
# subnet_ids = ["subnet-xxxxx", "subnet-yyyyy"]

# Tags
tags = {
  Project = "FinancialBatchProcessor"
  Environment = "Development"
  ManagedBy = "Terraform"
}
```

### Passo 3: Implantar a infraestrutura

```bash
# Inicializar Terraform
terraform init

# Validar configuração
terraform validate

# Planejar implantação
terraform plan -out=tfplan

# Revisar o plano com atenção
# Aplicar infraestrutura
terraform apply tfplan

# Salvar outputs
terraform output > ../outputs.txt
```

**Recursos esperados**:

- Bucket S3 para transações
- Bucket S3 para scripts do Glue
- Tabela DynamoDB para dados de clientes
- Domínio OpenSearch
- Definição do job Glue
- Papéis e políticas IAM
- Grupos de log CloudWatch

### Passo 4: Gerar dados de teste

```bash
cd ../data-generation

# Instalar dependências Python
pip install -r requirements.txt

# Configurar geração de dados
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
# Gerar dados de clientes e enviar para o DynamoDB
python generate_customers.py

# Gerar dados de transações e enviar para o S3
python generate_transactions.py

# Verificar dados
aws dynamodb scan --table-name customer-registration-dev --max-items 5
aws s3 ls s3://financial-transactions-dev-12345/transactions/ --recursive
```

### Passo 5: Compilar e implantar o job Glue

```bash
cd ../glue-job

# Limpar builds anteriores
sbt clean

# Compilar e empacotar
sbt package

# Verificar se o JAR foi criado
ls -lh target/scala-2.12/financial-transaction-processor_2.12-1.0.jar
```

```bash
# Obter bucket de scripts do Glue (output do Terraform)
GLUE_BUCKET=$(cd ../infrastructure && terraform output -raw glue_scripts_bucket)

# Enviar JAR para o S3
aws s3 cp target/scala-2.12/financial-transaction-processor_2.12-1.0.jar \
  s3://$GLUE_BUCKET/scripts/financial-transaction-processor_2.12-1.0.jar

# Verificar envio
aws s3 ls s3://$GLUE_BUCKET/scripts/
```

### Passo 6: Atualizar job Glue com local do script

```bash
cd ../infrastructure

# Atualizar job com local do script
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

### Passo 7: Executar o job Glue

```bash
# Iniciar execução para data específica
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

# Salvar ID da execução
JOB_RUN_ID=$(aws glue get-job-runs --job-name $JOB_NAME --max-results 1 --query 'JobRuns[0].Id' --output text)

echo "ID da execução: $JOB_RUN_ID"
```

### Passo 8: Monitorar a execução

```bash
# Verificar status
aws glue get-job-run \
  --job-name $JOB_NAME \
  --run-id $JOB_RUN_ID \
  --query 'JobRun.JobRunState' \
  --output text

# Ver logs no CloudWatch
LOG_GROUP="/aws-glue/jobs/output"
aws logs tail $LOG_GROUP --follow

# Procurar erros
aws logs filter-log-events \
  --log-group-name $LOG_GROUP \
  --filter-pattern "ERROR"
```

### Passo 9: Verificar dados no OpenSearch

```bash
# Obter endpoint OpenSearch
OPENSEARCH_ENDPOINT=$(cd infrastructure && terraform output -raw opensearch_endpoint)

# Saúde do cluster
curl -X GET "https://$OPENSEARCH_ENDPOINT/_cluster/health?pretty"

# Contar documentos no índice
curl -X GET "https://$OPENSEARCH_ENDPOINT/financial-transactions/_count?pretty"

# Consulta de exemplo
curl -X GET "https://$OPENSEARCH_ENDPOINT/financial-transactions/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 5,
    "query": {
      "match_all": {}
    }
  }'

# Consulta por tipo de transação
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

## Solução de problemas

### Problemas comuns

#### 1. Falha no Terraform apply

**Erro**: "Error creating S3 bucket: BucketAlreadyExists"

```bash
# Solução: Alterar nome do bucket em terraform.tfvars
# Nomes de buckets S3 devem ser globalmente únicos
```

**Erro**: "Error creating OpenSearch domain: InvalidTypeException"

```bash
# Solução: Verificar disponibilidade do tipo de instância na região
# Use: aws opensearch list-instance-types --region us-east-1
```

#### 2. Falha no job Glue

**Erro**: "Class not found"

```bash
# Solução: Verificar se o JAR foi enviado corretamente
aws s3 ls s3://$GLUE_BUCKET/scripts/

# Reenviar se necessário
sbt clean package
aws s3 cp target/scala-2.12/*.jar s3://$GLUE_BUCKET/scripts/
```

**Erro**: "Access Denied to DynamoDB"

```bash
# Solução: Verificar permissões do papel IAM
aws iam get-role-policy \
  --role-name glue-job-role \
  --policy-name dynamodb-access
```

#### 3. Problemas na geração de dados

**Erro**: "Unable to locate credentials"

```bash
# Solução: Configurar credenciais AWS
aws configure
```

**Erro**: "Table does not exist"

```bash
# Solução: Verificar se a tabela DynamoDB foi criada
aws dynamodb describe-table --table-name customer-registration-dev
```

#### 4. Problemas de acesso ao OpenSearch

**Erro**: "Connection timeout"

```bash
# Solução: Verificar regras do security group
# Se usar VPC, conferir configuração de rede
# Se público, verificar lista de IPs na política de acesso
```

### Checklist de validação

- [ ] Terraform apply concluído com sucesso
- [ ] Buckets S3 criados e acessíveis
- [ ] Tabela DynamoDB criada com esquema correto
- [ ] Domínio OpenSearch ativo e saudável
- [ ] Job Glue criado com configuração correta
- [ ] Papéis IAM com permissões necessárias
- [ ] Dados de teste gerados (20+ clientes, 1000+ transações)
- [ ] JAR do job Glue enviado para o S3
- [ ] Job Glue executado com sucesso
- [ ] Dados visíveis no OpenSearch
- [ ] Logs CloudWatch disponíveis

## Limpeza

Para destruir todos os recursos:

```bash
# Excluir dados do índice OpenSearch (opcional)
curl -X DELETE "https://$OPENSEARCH_ENDPOINT/financial-transactions"

# Esvaziar buckets S3
aws s3 rm s3://$S3_BUCKET --recursive
aws s3 rm s3://$GLUE_BUCKET --recursive

# Destruir infraestrutura
cd infrastructure
terraform destroy

# Confirmar destruição
# Digite: yes
```

## Considerações para implantação em produção

### Reforço de segurança

1. **Habilitar VPC para OpenSearch**
   - Implantar em subnet privada
   - Usar VPC endpoints
   - Restringir regras de security group

2. **Habilitar criptografia**
   - S3: SSE-KMS
   - DynamoDB: Criptografia KMS
   - OpenSearch: Criptografia em repouso e em trânsito

3. **Boas práticas IAM**
   - Menor privilégio
   - MFA para operações sensíveis
   - Rotação regular de credenciais

### Alta disponibilidade

1. **Implantação Multi-AZ**
   - OpenSearch: 3 nós em AZs diferentes
   - DynamoDB: Tabelas globais (opcional)

2. **Backup e recuperação**
   - Recuperação point-in-time no DynamoDB
   - Snapshots automatizados no OpenSearch
   - Versionamento e políticas de ciclo de vida no S3

### Monitoramento e alertas

1. **Alarmes CloudWatch**
   - Falhas do job Glue
   - Throttling no DynamoDB
   - Saúde do cluster OpenSearch
   - Taxas de erro elevadas

2. **Dashboards**
   - Criar dashboard no CloudWatch
   - Acompanhar métricas principais
   - Configurar notificações SNS

### Otimização de custos

1. **Dimensionamento**
   - Começar com instâncias menores
   - Ajustar conforme métricas
   - Savings Plans para cargas previsíveis

2. **Ciclo de vida dos dados**
   - Arquivar dados antigos do S3 no Glacier
   - Excluir índices antigos do OpenSearch
   - DynamoDB on-demand para cargas variáveis

## Próximos passos

Após implantação bem-sucedida:

1. Consultar [DEMO.md](DEMO.md) para preparação da demo
2. Testar com partições de datas diferentes
3. Acompanhar métricas de desempenho
4. Otimizar conforme a carga real
5. Implementar funcionalidades adicionais conforme necessário
