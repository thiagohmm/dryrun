# Processamento do job Scala em detalhes

Este documento descreve **o que o código Scala faz** e **como ele é executado** no pipeline de transações financeiras (AWS Glue + Spark).

---

## 1. Quando e como o código é executado

### Execução automática / disparo

O job **não roda sozinho no sentido de “sempre ligado”**. Ele é um **job em lote (batch)** que é **disparado** quando:

1. **Você inicia manualmente** (por exemplo):

   ```bash
   aws glue start-job-run --job-name financial-transaction-processor \
     --arguments='--year=2024,--month=01,--day=15'
   ```

2. **Um agendamento (schedule)** chama o Glue (por exemplo via EventBridge), passando ano/mês/dia.
3. **Outro sistema** chama a API do Glue (`StartJobRun`) com os argumentos.

Ou seja: o **código Scala é executado automaticamente** assim que **uma execução do job Glue** é iniciada (manual ou agendada). A partir daí, o que o job faz é totalmente definido pelo código descrito abaixo.

### Onde roda

- O JAR do job é carregado pelo **AWS Glue** a partir do S3.
- O Glue sobe um cluster **Spark** (versão 4.0) e executa a classe **`FinancialTransactionProcessor`**, método **`main`**.
- O código roda nos **workers** do Glue (máquinas Spark), com acesso a S3, DynamoDB e OpenSearch conforme as permissões IAM do job.

---

## 2. Visão geral do que o código faz

Em uma frase: **lê transações de um dia no S3, enriquece com dados de clientes do DynamoDB e grava as transações enriquecidas no OpenSearch.**

Fluxo em alto nível:

```
S3 (JSON, um dia) → Spark (leitura + enriquecimento) → OpenSearch (índice searchable)
                          ↑
                    DynamoDB (clientes)
```

O restante do documento detalha **cada etapa** do código.

---

## 3. Entrada: argumentos do job

O job recebe argumentos (via Glue) que definem **qual dia processar** e **quais recursos usar**:

| Argumento             | Exemplo                         | Uso                             |
| --------------------- | ------------------------------- | ------------------------------- |
| `JOB_NAME`            | financial-transaction-processor | Nome do job no Glue             |
| `year`                | 2024                            | Ano da partição de dados        |
| `month`               | 01                              | Mês                             |
| `day`                 | 15                              | Dia                             |
| `s3_bucket`           | meu-bucket                      | Bucket onde estão as transações |
| `dynamodb_table`      | customer-registration-dev       | Tabela de clientes              |
| `opensearch_endpoint` | xxx.es.amazonaws.com            | Endpoint do domínio OpenSearch  |
| `opensearch_index`    | financial-transactions          | Nome do índice                  |
| `aws_region`          | us-east-1                       | Região AWS                      |

O código usa **GlueArgParser** para ler esses argumentos e repassá-los para a lógica de processamento.

---

## 4. Método `main`: inicialização e orquestração

O método **`main`** é o ponto de entrada. Ele:

1. **Registra** o início do processamento em log.
2. **Interpreta os argumentos** do job (lista acima) com `GlueArgParser.getResolvedOptions`.
3. **Cria o SparkContext e o GlueContext** e obtém a `SparkSession`.
4. **Inicializa o job no Glue** com `Job.init` (para bookmarks e métricas do Glue).
5. **Chama** `processTransactions(...)` com todos os parâmetros (bucket, ano/mês/dia, tabela DynamoDB, endpoint e índice OpenSearch, região).
6. Se tudo der certo: **confirma o job** com `Job.commit()` e registra sucesso.
7. Em caso de exceção: **loga o erro** e **relança** a exceção (o Glue marca o run como falha).
8. No **`finally`**: **encerra o Spark** com `spark.stop()`.

Ou seja: o `main` **não** processa dados; ele só **prepara o ambiente** e **chama** a função que de fato lê, enriquece e grava.

---

## 5. Função `processTransactions`: o que acontece em detalhes

Esta função contém toda a lógica de negócio. As etapas são as seguintes.

### 5.1 Montagem do caminho S3 e leitura

- **Caminho lido**:  
  `s3://{s3Bucket}/transactions/year={year}/month={month}/day={day}/`

- O Spark **lê todos os arquivos JSON** desse prefixo (formato esperado: um JSON por linha ou array de objetos, conforme o Spark inferir).

- Opções usadas:
  - `inferSchema = true`: o Spark infere tipos (números, datas, strings).
  - `timestampFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"`: interpreta corretamente os campos de data/hora.

- O resultado é convertido em **`Dataset[Transaction]`** (tipagem forte; os nomes dos campos vêm do JSON em snake_case, ex.: `codigo_lancamento`, `numero_unico_conta`).

- É feito um **`count()`** para saber quantas transações existem; se for zero, a função **retorna** sem fazer enriquecimento nem escrita no OpenSearch.

### 5.2 Garantia de que o índice OpenSearch existe

- É criado um **`OpenSearchSink`** (endpoint + nome do índice).
- É chamado **`createIndexIfNotExists()`**:
  - Verifica se o índice existe.
  - Se não existir, **cria o índice** com o mapeamento definido no código (campos em camelCase: `codigoLancamento`, `numeroUnicoConta`, etc.) e configurações (ex.: shards, réplicas, refresh).

Assim, o restante do código pode assumir que o índice está pronto para receber documentos.

### 5.3 Enriquecimento com `mapPartitions` (DynamoDB)

- **`transactions.rdd.mapPartitions { partition => ... }`** faz com que cada **partição Spark** seja processada **uma vez** por um único bloco de código, que recebe um **iterator** de `Transaction`.

- Para **cada partição**:
  - Cria **um** **`DynamoDBEnricher`** (uma “conexão”/uso do DynamoDB por partição).
  - **Não** converte a partição inteira em lista na memória; usa **chunks** de tamanho fixo (`EnrichmentChunkSize = 1000`):
    - **`partition.grouped(EnrichmentChunkSize)`**: processa a partição em blocos de até 1000 transações.
  - Para **cada chunk**:
    - Extrai os **IDs de conta únicos** do chunk: `chunk.map(_.numero_unico_conta).toSet`.
    - Chama **`enricher.batchGetCustomerData(uniqueAccountIds)`** para buscar no DynamoDB os clientes correspondentes (em lotes de até 100, conforme limite da API).
    - Para cada transação do chunk, **monta** uma **`EnrichedTransaction`** juntando:
      - dados da **transação** (já em memória no chunk);
      - dados do **cliente** (se existir no mapa retornado pelo DynamoDB; senão, campos de cliente ficam `None`).
    - Devolve um **iterator** de `EnrichedTransaction` para aquele chunk.
  - O **`flatMap`** concatena os iterators de todos os chunks, então a partição inteira vira um único **iterator de transações enriquecidas**.
  - No **`finally`** da partição: **`enricher.close()`** para liberar o cliente DynamoDB.

- Resultado: um **RDD** (na prática, um “fluxo”) de **`EnrichedTransaction`**, ainda em memória/Spark, **sem** ter escrito nada no OpenSearch até aqui.

### 5.4 Escrita no OpenSearch com `foreachPartition`

- **`enrichedTransactions.foreachPartition { partition => ... }`** percorre cada partição do RDD de transações enriquecidas.

- Para **cada partição**:
  - Cria **um** **`OpenSearchSink`** (um cliente OpenSearch por partição).
  - Chama **`sink.writeBulk(partition)`**: o `partition` é um **iterator** de `EnrichedTransaction`.
    - O sink agrupa as transações em **lotes** (ex.: 1000) e, para cada lote, monta uma **requisição bulk** do OpenSearch (múltiplos “index” em uma única chamada HTTP).
    - Cada documento é serializado em JSON (campos em camelCase) e indexado com **ID = `codigoLancamento`** (evita duplicatas ao reindexar).
    - Há **retry** com backoff em caso de falha da requisição bulk.
  - No **`finally`**: **`sink.close()`** para fechar o cliente OpenSearch.

- Nenhum valor é “retornado” pelo `foreachPartition`; o efeito é **só** escrever no OpenSearch.

### 5.5 Estatísticas finais

- **`enrichedTransactions.count()`** força a computação de todo o RDD (leitura S3 + enriquecimento); o resultado é o número de transações enriquecidas.
- São **logadas**:
  - total de transações enriquecidas;
  - taxa de enriquecimento (porcentagem em relação ao total lido do S3).

Isso encerra a função **`processTransactions`**. O `main` então faz **commit** e **para o Spark**.

---

## 6. Componentes auxiliares (resumo do que fazem)

### 6.1 Modelos (`models/Transaction.scala`)

- **`Transaction`**: espelho do JSON do S3 (snake_case). Usado na leitura e dentro do `mapPartitions`.
- **`CustomerData`**: espelho dos itens da tabela DynamoDB (cadastro de clientes). Usado pelo `DynamoDBEnricher`.
- **`EnrichedTransaction`**: modelo de saída para o OpenSearch (camelCase), com campos de cliente em **`Option`** (podem ser `None` se o cliente não existir no DynamoDB).
- **`EnrichedTransaction.fromTransactionAndCustomer`**: monta uma `EnrichedTransaction` a partir de uma `Transaction` e de um `Option[CustomerData]`.

### 6.2 DynamoDBEnricher (`enrichment/DynamoDBEnricher.scala`)

- **Responsabilidade**: buscar dados de clientes no DynamoDB a partir de um conjunto de IDs de conta.
- **`batchGetCustomerData(accountIds)`**:
  - Divide os IDs em grupos de **100** (limite da API BatchGetItem).
  - Para cada grupo, chama **`batchGetWithRetry`** (até 3 tentativas com backoff).
  - **`performBatchGet`** monta a `BatchGetItemRequest`, envia ao DynamoDB e trata **UnprocessedKeys** (throttling) com retries e backoff.
  - Converte os itens retornados em **`CustomerData`** e devolve um **`Map[String, CustomerData]`** (chave = `numero_unico_conta`).
- **`close()`**: encerra o cliente DynamoDB.

### 6.3 OpenSearchSink (`sink/OpenSearchSink.scala`)

- **Responsabilidade**: escrever transações enriquecidas no OpenSearch em massa.
- **`createIndexIfNotExists()`**: verifica se o índice existe; se não, cria com mapeamento e settings definidos no código.
- **`writeBulk(transactions: Iterator[EnrichedTransaction])`**:
  - Agrupa as transações em lotes (ex.: 1000).
  - Para cada lote: monta um **BulkRequest** (vários `IndexRequest`), serializa cada `EnrichedTransaction` em JSON e chama **`executeBulkWithRetry`** (até 3 tentativas com backoff).
- **`close()`**: fecha o cliente OpenSearch.

---

## 7. Resumo do fluxo de dados (passo a passo)

1. **Disparo**: alguém ou algo chama `StartJobRun` no Glue com ano/mês/dia e configurações (bucket, tabela, endpoint, índice, região).
2. **Início**: Glue sobe o Spark e executa `FinancialTransactionProcessor.main`.
3. **Argumentos**: o código lê os parâmetros do job e chama `processTransactions`.
4. **Leitura**: Spark lê do S3 `transactions/year=.../month=.../day=.../` e obtém um `Dataset[Transaction]`.
5. **Índice**: OpenSearchSink garante que o índice exista (cria se necessário).
6. **Enriquecimento**: para cada partição Spark, em chunks de 1000 transações, o código busca clientes no DynamoDB (batch-get) e monta `EnrichedTransaction`; o resultado é um RDD de transações enriquecidas.
7. **Escrita**: cada partição desse RDD é enviada ao OpenSearch em lotes (bulk), com retry em caso de falha.
8. **Fim**: é calculado o `count` para estatísticas, o job é commitado e o Spark é encerrado.

---

## 8. Tabela resumo: “O que o código faz”

| Etapa              | Onde no código                                            | O que faz                                                                         |
| ------------------ | --------------------------------------------------------- | --------------------------------------------------------------------------------- |
| Ler argumentos     | `main` → GlueArgParser                                    | Define ano/mês/dia, bucket, tabela, endpoint, índice, região                      |
| Iniciar Spark/Glue | `main`                                                    | Cria contextos e chama `processTransactions`                                      |
| Ler S3             | `processTransactions` → `spark.read.json(s3Path)`         | Carrega transações do dia como `Dataset[Transaction]`                             |
| Garantir índice    | `OpenSearchSink.createIndexIfNotExists`                   | Cria índice OpenSearch se não existir                                             |
| Enriquecer         | `mapPartitions` + `DynamoDBEnricher.batchGetCustomerData` | Por partição, em chunks, busca clientes no DynamoDB e monta `EnrichedTransaction` |
| Gravar OpenSearch  | `foreachPartition` + `OpenSearchSink.writeBulk`           | Envia transações enriquecidas em bulk para o OpenSearch                           |
| Estatísticas       | `enrichedTransactions.count()` + logs                     | Total enriquecido e taxa de enriquecimento                                        |
| Encerrar           | `main` → `Job.commit()` e `spark.stop()`                  | Marca job como sucesso e desliga o Spark                                          |

Com isso, você tem uma descrição objetiva de **como o código Scala é executado** (por disparo do job Glue) e **o que ele faz em detalhes** em cada etapa.
