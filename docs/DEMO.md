# Guia da demo

Este guia ajuda a preparar e executar uma demonstração bem-sucedida do pipeline de processamento em lote com AWS Glue.

## Checklist pré-demo

### Verificação da infraestrutura

- [ ] Todos os recursos Terraform implantados com sucesso
- [ ] Buckets S3 criados e acessíveis
- [ ] Tabela DynamoDB populada com dados de clientes
- [ ] Domínio OpenSearch ativo e saudável
- [ ] Job Glue configurado corretamente
- [ ] Papéis e permissões IAM verificados

### Verificação dos dados

- [ ] Pelo menos 20 contas de clientes distintas no DynamoDB
- [ ] Pelo menos 1000 registros de transações no S3
- [ ] Dados particionados corretamente por ano/mês/dia
- [ ] Consultas de exemplo testadas no OpenSearch

### Preparação do código

- [ ] JAR do job Glue compilado e enviado
- [ ] Todo o código-fonte revisado e compreendido
- [ ] Comentários nas partes mais complexas
- [ ] Explicação do código preparada

## Roteiro da demo

### Parte 1: Introdução (5 minutos)

**Pontos a abordar**:

- Visão geral e objetivos do projeto
- Componentes da arquitetura
- Desafios técnicos enfrentados
- Tempo investido no desenvolvimento

**Mostrar**:

```bash
# Estrutura do projeto
tree -L 2 -I 'target|.terraform'

# Mostrar README
cat README.md
```

### Parte 2: Arquitetura (10 minutos)

**Pontos a abordar**:

- Fluxo de dados S3 → Glue → DynamoDB → OpenSearch
- Por que MapPartitions para processamento em lote
- Otimização batch-get no DynamoDB
- Estratégia de indexação no OpenSearch

**Mostrar**:

```bash
# Diagrama da arquitetura
cat docs/ARCHITECTURE.md

# Infraestrutura Terraform
cd infrastructure
terraform show | head -50
```

### Parte 3: Infraestrutura como código (10 minutos)

**Demonstrar configuração Terraform**:

```bash
# Configuração principal
cat infrastructure/main.tf

# Configuração S3
cat infrastructure/s3.tf

# Configuração DynamoDB
cat infrastructure/dynamodb.tf

# Configuração Glue
cat infrastructure/glue.tf

# Configuração OpenSearch
cat infrastructure/opensearch.tf

# Estado atual
terraform state list

# Outputs
terraform output
```

**Explicar**:

- Dependências entre recursos
- Configurações de segurança
- Considerações de escalabilidade
- Estratégias de otimização de custos

### Parte 4: Geração de dados (5 minutos)

**Mostrar criação dos dados de teste**:

```bash
cd ../data-generation

# Script de geração de clientes
cat generate_customers.py | head -50

# Script de geração de transações
cat generate_transactions.py | head -50

# Configuração
cat config.json

# Dados gerados de exemplo
aws dynamodb scan --table-name customer-registration-dev --max-items 3

# Estrutura dos dados no S3
aws s3 ls s3://SEU-BUCKET/transactions/ --recursive | head -10
```

**Explicar**:

- Conformidade com o esquema de dados
- Geração de dados realistas
- Requisitos de volume (1000+ transações, 20+ contas)

### Parte 5: Implementação do job Glue (15 minutos)

**Passeio pelo código**:

```bash
cd ../glue-job

# Configuração de build
cat build.sbt

# Processador principal
cat src/main/scala/FinancialTransactionProcessor.scala

# Modelos de dados
cat src/main/scala/models/Transaction.scala
cat src/main/scala/models/CustomerData.scala

# Lógica de enriquecimento DynamoDB
cat src/main/scala/enrichment/DynamoDBEnricher.scala

# Sink OpenSearch
cat src/main/scala/sink/OpenSearchSink.scala
```

**Pontos a explicar**:

1. **Implementação MapPartitions**:

   ```scala
   // Explicar este padrão
   df.mapPartitions { partition =>
     // Extrair IDs de conta únicos da partição
     val accountIds = partition.map(_.numeroUnicoConta).toSet

     // Um único batch-get para toda a partição
     val customerData = batchGetFromDynamoDB(accountIds)

     // Enriquecer todas as transações da partição
     partition.map(txn => enrichTransaction(txn, customerData))
   }
   ```

2. **DynamoDB Batch-Get**:

   ```scala
   // Explicar estratégia de lotes (máx. 100 itens)
   def batchGetFromDynamoDB(accountIds: Set[String]): Map[String, CustomerData] = {
     accountIds.grouped(100).flatMap { batch =>
       // Requisição batch-get
       val request = new BatchGetItemRequest()
         .withRequestItems(...)

       dynamoDBClient.batchGetItem(request)
     }.toMap
   }
   ```

3. **Transformação camelCase**:

   ```scala
   // Explicar conversão de nomes de campos
   def toCamelCase(snakeCase: String): String = {
     // Detalhes da implementação
   }
   ```

4. **Tratamento de erros**:
   ```scala
   // Explicar lógica de retry
   def withRetry[T](maxRetries: Int)(fn: => T): T = {
     // Implementação de backoff exponencial
   }
   ```

### Parte 6: Execução ao vivo (10 minutos)

**Executar o pipeline**:

```bash
# Obter nome do job
JOB_NAME=$(cd infrastructure && terraform output -raw glue_job_name)

# Iniciar execução
aws glue start-job-run \
  --job-name $JOB_NAME \
  --arguments '{
    "--year":"2024",
    "--month":"01",
    "--day":"15"
  }'

# Obter ID da execução
RUN_ID=$(aws glue get-job-runs --job-name $JOB_NAME --max-results 1 \
  --query 'JobRuns[0].Id' --output text)

echo "ID da execução: $RUN_ID"

# Acompanhar status
watch -n 5 "aws glue get-job-run --job-name $JOB_NAME --run-id $RUN_ID \
  --query 'JobRun.JobRunState' --output text"
```

**Mostrar logs CloudWatch**:

```bash
# Acompanhar logs em tempo real
aws logs tail /aws-glue/jobs/output --follow --since 5m

# Eventos de log específicos
aws logs filter-log-events \
  --log-group-name /aws-glue/jobs/output \
  --filter-pattern "Processing partition" \
  --max-items 10
```

### Parte 7: Verificação dos resultados (10 minutos)

**Consultar OpenSearch**:

```bash
# Obter endpoint OpenSearch
OPENSEARCH_ENDPOINT=$(cd infrastructure && terraform output -raw opensearch_endpoint)

# Saúde do cluster
curl -X GET "https://$OPENSEARCH_ENDPOINT/_cluster/health?pretty"

# Contar documentos
curl -X GET "https://$OPENSEARCH_ENDPOINT/financial-transactions/_count?pretty"

# Documentos enriquecidos de exemplo
curl -X GET "https://$OPENSEARCH_ENDPOINT/financial-transactions/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 3,
    "query": { "match_all": {} }
  }'
```

**Demonstrar enriquecimento**:

```bash
# Consulta com campos enriquecidos
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

**Consultas analíticas**:

```bash
# Agregação por tipo de transação
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

# Agregação por tipo de produto
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

# Soma do valor total das transações
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

### Parte 8: Métricas de desempenho (5 minutos)

**Métricas do job**:

```bash
# Detalhes da execução
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

**Discutir**:

- Tempo de processamento para 1000+ registros
- Eficiência do batch-get no DynamoDB
- Desempenho da indexação no OpenSearch
- Custo por execução

### Parte 9: Qualidade do código e boas práticas (5 minutos)

**Destacar**:

1. **Programação funcional**:
   - Estruturas de dados imutáveis
   - Funções puras
   - Segurança de tipos

2. **Tratamento de erros**:
   - Blocos Try/Catch
   - Mecanismos de retry
   - Logging

3. **Otimização de desempenho**:
   - MapPartitions para lotes
   - Consultas eficientes ao DynamoDB
   - Inserções em massa no OpenSearch

4. **Organização do código**:
   - Separação de responsabilidades
   - Design modular
   - Nomenclatura clara

5. **Considerações de teste**:
   - Componentes testáveis
   - Cenários de teste de integração
   - Validação de dados

### Parte 10: Q&A e discussão (10 minutos)

**Respostas preparadas para perguntas comuns**:

**P: Por que MapPartitions em vez de map?**  
R: MapPartitions permite fazer batch de requisições ao DynamoDB por partição, reduzindo as chamadas de API de milhares para dezenas, melhorando desempenho e custo.

**P: Como o batch-get lida com dados de cliente ausentes?**  
R: A lógica de enriquecimento trata null e valores padrão. Transações sem cliente correspondente são processadas com campos de enriquecimento nulos, que podem ser filtrados nas consultas ao OpenSearch.

**P: O que acontece se o job Glue falhar no meio?**  
R: Os jobs são idempotentes. Podemos reexecutar para a mesma partição de data. O OpenSearch usa IDs de documento (codigoLancamento) para evitar duplicatas com upsert.

**P: Como escalar para milhões de registros?**  
R: Aumentar workers do Glue (10–50), otimizar tamanho das partições, usar cluster OpenSearch maior, considerar capacidade provisionada no DynamoDB e processamento incremental.

**P: E problemas de qualidade de dados?**  
R: Validamos o esquema na leitura, tratamos nulls e registramos problemas. Em produção, adicionaríamos regras do AWS Glue Data Quality.

**P: Considerações de segurança?**  
R: Implantação em VPC para OpenSearch, criptografia KMS em todos os armazenamentos, IAM com menor privilégio, auditoria via CloudTrail e isolamento de rede.

## Relatório de acompanhamento de tempo

**Modelo para a demo**:

```
Detalhamento do tempo de desenvolvimento:
- Infraestrutura (Terraform): X horas
- Job Glue (Scala): Y horas
- Geração de dados: Z horas
- Testes e depuração: W horas
- Documentação: V horas
Total: XX horas
```

## Dicas para a demo

### Fazer:

✅ Testar tudo antes da demo  
✅ Ter plano B para demos ao vivo  
✅ Explicar o raciocínio  
✅ Mostrar código e resultados  
✅ Estar preparado para perguntas  
✅ Demonstrar entendimento de cada parte do código  
✅ Destacar desafios superados  
✅ Mostrar monitoramento e logging

### Evitar:

❌ Explicar com pressa  
❌ Pular a parte de tratamento de erros  
❌ Ignorar desempenho  
❌ Omitir limitações  
❌ Dizer que usou IA (proibido)  
❌ Ir sem preparo para perguntas sobre código

## Planos de contingência

### Se a execução ao vivo falhar:

1. **Ter resultados pré-gravados**:
   - Capturas de tela de execuções bem-sucedidas
   - Exemplos de consultas e resultados no OpenSearch
   - Logs CloudWatch de execuções anteriores

2. **Explicar o problema**:
   - Mostrar como faria o debug
   - Demonstrar capacidade de troubleshooting
   - Comentar como resolveria

3. **Mostrar evidências alternativas**:
   - Resultados de testes unitários
   - Execução local em Scala
   - Exemplos de transformações de dados

## Entregáveis pós-demo

**Conteúdo do arquivo ZIP**:

```
financial-batch-processor.zip
├── infrastructure/          # Todos os arquivos Terraform
├── glue-job/               # Todo o código-fonte Scala
├── data-generation/        # Scripts Python
├── docs/                   # Documentação
├── README.md
├── .gitignore
├── Makefile
└── TIME_TRACKING.md        # Seu relatório de tempo investido
```

**Criar o entregável**:

```bash
# Na raiz do projeto
zip -r financial-batch-processor.zip . \
  -x "*.terraform/*" \
  -x "*/target/*" \
  -x "*/__pycache__/*" \
  -x "*.tfstate*" \
  -x "*/.git/*"

# Verificar conteúdo
unzip -l financial-batch-processor.zip
```

## Critérios de sucesso

- [ ] Todos os requisitos funcionais atendidos
- [ ] Todos os requisitos não funcionais atendidos
- [ ] Código limpo e bem documentado
- [ ] Execução ao vivo bem-sucedida
- [ ] Explicação clara da arquitetura
- [ ] Compreensão de todo o código demonstrada
- [ ] Apresentação profissional
- [ ] Acompanhamento de tempo informado

## Checklist final

Antes da demo:

- [ ] Ensaiar a demo pelo menos duas vezes
- [ ] Verificar se todos os recursos AWS estão ativos
- [ ] Testar todos os comandos do roteiro
- [ ] Preparar respostas para perguntas prováveis
- [ ] Ter capturas de tela de backup
- [ ] Carregar o notebook e ter o carregador
- [ ] Testar compartilhamento de tela se for remoto
- [ ] Revisar todo o código uma última vez
- [ ] Preparar relatório de acompanhamento de tempo
- [ ] Criar o arquivo ZIP de entrega

Boa sorte na sua demo! 🚀
