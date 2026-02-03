# Documentação da arquitetura

## Visão geral do sistema

Este documento descreve a arquitetura do pipeline de processamento em lote com AWS Glue para transações financeiras.

## Diagrama da arquitetura

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Ambiente em nuvem AWS                             │
│                                                                       │
│  ┌──────────────┐                                                    │
│  │ Bucket S3    │                                                    │
│  │              │                                                    │
│  │ Particionado │                                                    │
│  │ por data:    │                                                    │
│  │ /year=/month │                                                    │
│  │ /day/        │                                                    │
│  │              │                                                    │
│  │ Arquivos JSON│                                                    │
│  └──────┬───────┘                                                    │
│         │                                                            │
│         │ Leitura                                                    │
│         ▼                                                            │
│  ┌──────────────────────────────────────────┐                       │
│  │      Job AWS Glue (Scala 2.12)          │                       │
│  │                                          │                       │
│  │  ┌────────────────────────────────────┐ │                       │
│  │  │  1. Ler do S3                      │ │                       │
│  │  │  2. Parse JSON para DataFrame      │ │                       │
│  │  │  3. Processamento MapPartitions:   │ │                       │
│  │  │     - Agrupar por partição         │ │                       │
│  │  │     - Extrair IDs de conta únicos  │ │                       │
│  │  │     - Batch-get no DynamoDB        │ │◄──────┐              │
│  │  │     - Enriquecer transações       │ │       │              │
│  │  │     - Transformar para camelCase  │ │       │              │
│  │  │  4. Gravar no OpenSearch          │ │       │              │
│  │  └────────────────────────────────────┘ │       │              │
│  └──────────────┬───────────────────────────┘       │              │
│                 │                                   │              │
│                 │                            ┌──────┴──────────┐   │
│                 │                            │   DynamoDB      │   │
│                 │                            │                 │   │
│                 │                            │  Dados clientes │   │
│                 │                            │  Tabela         │   │
│                 │                            │                 │   │
│                 │                            │  API Batch-Get │   │
│                 │                            └─────────────────┘   │
│                 │                                                  │
│                 │ Gravação                                         │
│                 ▼                                                  │
│  ┌──────────────────────────────┐                                 │
│  │     Domínio OpenSearch       │                                 │
│  │                              │                                 │
│  │  Índice: financial-txns      │                                 │
│  │  Formato: JSON camelCase     │                                 │
│  │                              │                                 │
│  │  Dados de transação enriquecidos                               │
│  └──────────────────────────────┘                                 │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Detalhes dos componentes

### 1. Bucket S3 (Data Lake)

**Finalidade**: Armazenar dados brutos de transações financeiras

**Estrutura**:

```
s3://bucket-transacoes-financeiras/
└── transactions/
    └── year=2024/
        └── month=01/
            └── day=15/
                ├── transactions_001.json
                ├── transactions_002.json
                └── transactions_003.json
```

**Formato dos dados**: JSON (snake_case)

**Estratégia de particionamento**:

- Particionamento ano/mês/dia para consultas eficientes
- Permite processamento incremental
- Suporta políticas de retenção por tempo

### 2. Job AWS Glue

**Runtime**: Glue 4.0  
**Linguagem**: Scala 2.12  
**Tipo de worker**: G.1X (recomendado) ou G.2X para conjuntos maiores  
**Número de workers**: 2–10 (configurável conforme volume)

**Fluxo de processamento**:

1. **Ingestão de dados**
   - Ler arquivos JSON particionados do S3
   - Converter para Spark DataFrame
   - Validar esquema

2. **Enriquecimento em lote (MapPartitions)**

   ```scala
   df.mapPartitions { partition =>
     val accountIds = partition.map(_.numero_unico_conta).toSet
     val customerData = batchGetFromDynamoDB(accountIds)
     partition.map(txn => enrichTransaction(txn, customerData))
   }
   ```

3. **Transformação de dados**
   - Converter snake_case para camelCase
   - Mesclar dados de transação e cliente
   - Aplicar regras de negócio

4. **Carregamento**
   - Inserção em massa no OpenSearch
   - Tratamento de erros e retries

**Recursos principais**:

- **MapPartitions**: Reduz chamadas ao DynamoDB ao processar em lote por partição
- **Batch-Get**: Até 100 itens por requisição ao DynamoDB
- **Tratamento de erros**: Retry com backoff exponencial
- **Logging**: Integração com CloudWatch para monitoramento

### 3. Tabela DynamoDB

**Nome da tabela**: customer-registration  
**Chave primária**: numero_unico_conta (String)  
**Modo de capacidade**: On-Demand (autoescala)

**Atributos**:

- numero_unico_conta (PK)
- nome_titular_conta
- data_nascimento_titular_conta
- zip-code
- data_criacao_registro

**Padrão de acesso**:

- Operações batch-get (até 100 itens)
- Carga com muitas leituras
- Requisitos de baixa latência

### 4. Domínio OpenSearch

**Versão**: OpenSearch 2.x  
**Tipo de instância**: t3.small.search (dev) ou r6g.large.search (prod)  
**Número de nós**: 1 (dev) ou 3 (prod com HA)  
**Armazenamento**: EBS (gp3)

**Configuração do índice**:

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

## Fluxo de dados

### Processamento passo a passo

1. **Gatilho**: Manual ou agendado (EventBridge)
2. **Leitura**: Job Glue lê da partição S3 (ex.: year=2024/month=01/day=15)
3. **Parse**: Arquivos JSON convertidos em Spark DataFrame
4. **Partição**: Dados distribuídos nas partições Spark
5. **Enriquecimento**: Para cada partição:
   - Extrair IDs de conta únicos
   - Batch-get de clientes no DynamoDB (máx. 100 por requisição)
   - Juntar transação com dados do cliente
6. **Transformação**: Converter para JSON camelCase
7. **Carregamento**: Inserção em massa no índice OpenSearch
8. **Conclusão**: Job registra métricas e finaliza

## Considerações de desempenho

### Estratégias de otimização

1. **Tamanho do lote**
   - DynamoDB: 100 itens por batch-get
   - OpenSearch: 1000 documentos por requisição bulk
   - Partições Spark: Conforme tamanho dos dados (128MB padrão)

2. **Paralelismo**
   - Executores Spark: 2–10 workers
   - Requisições concorrentes ao DynamoDB: Controladas pelo número de partições
   - Threads bulk OpenSearch: 2–4 por worker

3. **Memória**
   - Memória do worker: 8GB (G.1X) ou 16GB (G.2X)
   - Tamanho da partição: Manter abaixo de 128MB
   - Cache de dados de clientes dentro da partição

4. **Tratamento de erros**
   - Retry de requisições DynamoDB falhas (3 tentativas)
   - Dead letter queue para registros falhos
   - Alarmes CloudWatch para falhas do job

## Segurança

### Papéis e políticas IAM

1. **Papel do job Glue**
   - S3: Leitura do bucket de transações
   - DynamoDB: Permissão BatchGetItem
   - OpenSearch: Escrita
   - CloudWatch: Logs e métricas

2. **Segurança de rede**
   - VPC: Opcional (pode rodar em subnet pública)
   - Security Groups: Restringir acesso ao OpenSearch
   - Criptografia: Em repouso (S3, DynamoDB, OpenSearch) e em trânsito (TLS)

3. **Proteção de dados**
   - Criptografia do bucket S3 (SSE-S3 ou SSE-KMS)
   - Criptografia em repouso no DynamoDB
   - Criptografia em repouso e nó a nó no OpenSearch

## Monitoramento e logging

### Métricas CloudWatch

- Job Glue: Duração, horas DPU, taxa de sucesso/falha
- DynamoDB: Capacidade de leitura, eventos de throttling
- OpenSearch: Taxa de indexação, latência de busca, saúde do cluster

### Logging

- Logs do job Glue: CloudWatch Logs
- Logs de aplicação: Métricas customizadas e logging estruturado
- Logs de auditoria: CloudTrail para chamadas de API

## Escalabilidade

### Escala horizontal

- **Workers Glue**: De 2 a 10+ conforme volume
- **DynamoDB**: Modo on-demand escala automaticamente
- **OpenSearch**: Adicionar nós de dados para volumes maiores

### Escala vertical

- **Tipo de worker Glue**: De G.1X para G.2X
- **Instância OpenSearch**: Tipos de instância maiores

## Otimização de custos

1. **Glue**: Número e tipo adequados de workers
2. **DynamoDB**: On-demand para cargas variáveis
3. **OpenSearch**: Dimensionar instâncias, usar reserved instances
4. **S3**: Políticas de ciclo de vida para dados antigos (Glacier/Deep Archive)

## Recuperação de desastres

- **S3**: Replicação entre regiões (opcional)
- **DynamoDB**: Recuperação point-in-time habilitada
- **OpenSearch**: Snapshots automatizados para S3
- **Job Glue**: Controle de versão no Git, backup do JAR no S3

## Melhorias futuras

1. **Processamento em tempo real**: Incluir Kinesis Data Streams
2. **Qualidade de dados**: AWS Glue Data Quality
3. **Orquestração**: Step Functions para fluxos complexos
4. **Integração ML**: SageMaker para detecção de fraude
5. **Camada de API**: API Gateway para consultas ao OpenSearch
