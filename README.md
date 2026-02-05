# Pipeline de processamento em lote com AWS Glue

## Visão geral

Este projeto implementa um pipeline de processamento em lote para transações financeiras usando AWS Glue, DynamoDB e OpenSearch. A solução lê dados de transações do S3, enriquece com informações de clientes do DynamoDB e armazena os dados enriquecidos no OpenSearch para análise.

## Arquitetura

```
Bucket S3 (JSON) → Job AWS Glue (Scala) → DynamoDB (enriquecimento em lote) → OpenSearch
```

### Componentes

1. **Bucket S3**: Armazena dados de transações financeiras particionados por ano/mês/dia
2. **Job AWS Glue**: Job ETL em Scala usando MapPartitions para processamento em lote
3. **DynamoDB**: Dados de cadastro de clientes para enriquecimento
4. **OpenSearch**: Armazenamento final das transações enriquecidas

## Esquemas de dados

### Dados de transação no S3

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

### Dados de cliente no DynamoDB

```json
{
  "numero_unico_conta": "uuid",
  "nome_titular_conta": "João Silva",
  "data_nascimento_titular_conta": "1990-01-15T00:00:00Z",
  "zip-code": "12345-678",
  "data_criacao_registro": "2023-01-01"
}
```

### Dados enriquecidos no OpenSearch (camelCase)

```json
{
  "codigoLancamento": "uuid",
  "numeroUnicoConta": "uuid",
  "valorTotalTransacao": 100.5,
  "dataCompletaTransacao": "2024-01-15T10:30:00Z",
  "tipoTransacao": "CREDITO",
  "tipoProdutoTransacao": "PIX",
  "nomeTitularConta": "João Silva",
  "dataNascimentoTitularConta": "1990-01-15T00:00:00Z",
  "zipCode": "12345-678"
}
```

## Estrutura do projeto

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
├── glue-job/               # Job Glue em Scala
│   ├── build.sbt
│   └── src/main/scala/
│       ├── FinancialTransactionProcessor.scala
│       ├── models/
│       ├── enrichment/
│       └── sink/
├── data-generation/        # Geradores de dados de teste
│   ├── generate_transactions.py
│   ├── generate_customers.py
│   ├── requirements.txt
│   └── config.json
├── docs/                   # Documentação
│   ├── ARCHITECTURE.md
│   ├── DEPLOYMENT.md
│   └── DEMO.md
└── README.md
```

## Pré-requisitos

- Conta AWS com permissões adequadas
- Terraform >= 1.0
- Python >= 3.8
- Scala 2.12
- SBT (Scala Build Tool)
- AWS CLI configurado

## Início rápido

### 1. Implantar a infraestrutura

```bash
cd infrastructure
terraform init
terraform plan
terraform apply
```

### 2. Gerar dados de teste

```bash
cd data-generation
pip install -r requirements.txt
python generate_customers.py
python generate_transactions.py
```

### 3. Compilar e implantar o job Glue

```bash
cd glue-job
sbt clean package
# Enviar JAR para o S3 (saída do terraform output)
aws s3 cp target/scala-2.12/financial-transaction-processor_2.12-1.0.jar s3://SEU_BUCKET_GLUE_SCRIPTS/
```

### 4. Executar o job Glue

```bash
aws glue start-job-run --job-name financial-transaction-processor \
  --arguments='--year=2024,--month=01,--day=15'
```

## Requisitos técnicos atendidos

- ✅ Dados no S3 em formato JSON
- ✅ Saída no OpenSearch em JSON camelCase
- ✅ Job Glue em Scala
- ✅ MapPartitions para processamento em lote
- ✅ Operações batch-get no DynamoDB
- ✅ Infraestrutura como código (Terraform)
- ✅ Job Glue versão 4.0
- ✅ 1000+ registros de teste com 20+ contas distintas

## 📚 Documentação Adicional

### Guias de Início Rápido

- **[VISUAL_GUIDE.md](./VISUAL_GUIDE.md)** - 🎨 Guia visual do fluxo completo
- **[FAQ.md](./FAQ.md)** - ❓ Perguntas frequentes com respostas diretas
- **[JOB_EXECUTION.md](./JOB_EXECUTION.md)** - ▶️ Como executar o job Scala

### Setup e Deploy

- **[SETUP_AWS.md](./SETUP_AWS.md)** - 🔑 Configuração de credenciais AWS
- **[SCALA_DEPLOYMENT.md](./SCALA_DEPLOYMENT.md)** - 🚀 Deploy completo do job Scala
- **[deploy-full.sh](./deploy-full.sh)** - 🤖 Script automatizado de deployment

### Documentação Técnica

- **[docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md)** - 🏗️ Arquitetura detalhada
- **[docs/DEMO.md](./docs/DEMO.md)** - 🎬 Guia de demonstração
- **[docs/DEPLOYMENT.md](./docs/DEPLOYMENT.md)** - 📦 Deployment detalhado

### Comandos Rápidos

```bash
# Deploy completo (primeira vez)
./deploy-full.sh

# Ver todos os comandos disponíveis
make help

# Gerar dados de teste
make generate-data

# Executar job Scala
make run-glue

# Monitorar logs
aws logs tail /aws-glue/jobs/financial-transaction-processor --follow

# Destruir infraestrutura
make destroy
```

## 🎯 Início Rápido (TL;DR)

1. **Configurar AWS:**

   ```bash
   aws configure
   # Access Key: [SUA_ACCESS_KEY_AQUI]
   # Secret: [SUA_SECRET_KEY_AQUI]
   # Region: us-east-2
   ```

2. **Deploy tudo:**

   ```bash
   ./deploy-full.sh
   ```

3. **Gerar dados:**

   ```bash
   make generate-data
   ```

4. **Executar job:**
   ```bash
   make run-glue
   ```

## Acompanhamento de tempo de desenvolvimento

Registre o tempo de desenvolvimento e apresente durante a demo.

## Checklist da demo

- [ ] Infraestrutura implantada com sucesso (32 recursos)
- [ ] Job Scala compilado e deployed no S3
- [ ] Dados de teste gerados e enviados
- [ ] Job Glue executado sem erros
- [ ] Dados enriquecidos corretamente no OpenSearch
- [ ] Métricas de desempenho revisadas
- [ ] Logs CloudWatch funcionando
- [ ] Explicação do código preparada

## 💰 Custos Estimados

- **OpenSearch t3.small**: ~$35-40/mês
- **S3 + DynamoDB**: ~$1-2/mês
- **Glue Job execução**: ~$0.15 por execução (10 min)
- **Total**: ~$40-50/mês (ambiente dev)

## Licença

Este é um projeto de avaliação técnica.
