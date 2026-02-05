# 📖 Explicação Detalhada do Código Scala - Linha por Linha

## 🎯 Visão Geral do Fluxo

```
1. ENTRADA → Lê JSONs do S3 (transações)
2. PROCESSAMENTO → Enriquece com dados do DynamoDB (clientes)
3. SAÍDA → Grava no OpenSearch (transações enriquecidas)
```

---

## 📁 Estrutura de Arquivos

```
glue-job/src/main/scala/
├── FinancialTransactionProcessor.scala  ← MAIN: Orquestra todo o processo
├── enrichment/
│   └── DynamoDBEnricher.scala          ← Busca dados de clientes no DynamoDB
├── models/
│   └── Transaction.scala               ← Define estruturas de dados
└── sink/
    └── OpenSearchSink.scala            ← Grava dados no OpenSearch
```

---

# 🚀 ARQUIVO 1: FinancialTransactionProcessor.scala

## 📍 Onde começa: **Linha 1**

### 🎯 Propósito: **Arquivo principal que orquestra todo o processamento**

---

## 📦 IMPORTS (Linhas 1-10)

```scala
import com.amazonaws.services.glue.GlueContext
import com.amazonaws.services.glue.util.{GlueArgParser, Job}
```

**O que faz:**

- Importa classes do AWS Glue para integração com o serviço
- `GlueContext`: Contexto específico do Glue (extensão do Spark)
- `GlueArgParser`: Processa argumentos passados ao job
- `Job`: Gerencia o ciclo de vida do job (init, commit)

```scala
import enrichment.DynamoDBEnricher
import models.{EnrichedTransaction, Transaction}
```

**O que faz:**

- Importa classes customizadas do projeto
- `DynamoDBEnricher`: Classe que busca dados de clientes
- `Transaction`: Estrutura de dados da transação do S3
- `EnrichedTransaction`: Transação + dados do cliente

```scala
import org.apache.spark.SparkContext
import org.apache.spark.sql.{Dataset, SparkSession}
```

**O que faz:**

- Importa componentes do Apache Spark
- `SparkContext`: Contexto principal do Spark
- `Dataset`: Estrutura de dados tipada do Spark (type-safe)
- `SparkSession`: Interface unificada para Spark SQL

```scala
import sink.OpenSearchSink
import org.slf4j.LoggerFactory
import scala.collection.JavaConverters._
```

**O que faz:**

- `OpenSearchSink`: Classe para gravar no OpenSearch
- `LoggerFactory`: Cria logger para mensagens
- `JavaConverters`: Converte entre coleções Scala e Java

---

## 🏗️ DEFINIÇÃO DO OBJETO (Linhas 12-27)

```scala
object FinancialTransactionProcessor {
```

**O que é:**

- **Object** em Scala = Singleton (uma única instância)
- É o ponto de entrada do programa (contém o método `main`)

```scala
private val EnrichmentChunkSize = 1000
```

**O que faz:**

- Define que processará **1000 transações por vez**
- Evita carregar toda a partição na memória (previne OOM - Out of Memory)
- Cada chunk gera uma chamada batch ao DynamoDB

```scala
private val logger = LoggerFactory.getLogger(getClass)
```

**O que faz:**

- Cria um logger para registrar eventos
- Mensagens aparecem nos logs do CloudWatch

---

## 🎬 MÉTODO MAIN (Linhas 29-102)

```scala
def main(sysArgs: Array[String]): Unit = {
```

**O que é:**

- **Ponto de entrada do programa**
- Executado quando o job Glue inicia
- `sysArgs`: Argumentos passados via AWS Glue

### 📋 PARSING DE ARGUMENTOS (Linhas 32-49)

```scala
val args = GlueArgParser.getResolvedOptions(
  sysArgs,
  Array(
    "JOB_NAME",
    "year",
    "month",
    "day",
    "s3_bucket",
    "dynamodb_table",
    "opensearch_endpoint",
    "opensearch_index",
    "aws_region"
  )
)
```

**O que faz:**

- Extrai argumentos passados ao job
- Exemplo de execução:
  ```bash
  aws glue start-job-run \
    --job-name financial-transaction-processor \
    --arguments '{
      "--year":"2024",
      "--month":"02",
      "--day":"15",
      "--s3_bucket":"financial-transactions-dev-160885283918",
      ...
    }'
  ```

```scala
val jobName = args("JOB_NAME")
val year = args("year")
val month = args("month")
val day = args("day")
// ... extrai todos os argumentos
```

**O que faz:**

- Armazena cada argumento em uma variável
- `year`, `month`, `day`: Define qual partição de dados processar
- `s3_bucket`: De onde ler as transações
- `dynamodb_table`: De onde buscar dados de clientes
- `opensearch_endpoint`: Para onde gravar os resultados

```scala
logger.info(s"Job Parameters:")
logger.info(s"  Job Name: $jobName")
logger.info(s"  Date: $year-$month-$day")
// ... registra todos os parâmetros
```

**O que faz:**

- Loga os parâmetros recebidos
- Útil para debug nos logs do CloudWatch
- `s"..."` = String interpolation (substitui variáveis)

### ⚙️ INICIALIZAÇÃO SPARK/GLUE (Linhas 70-76)

```scala
val sparkContext = new SparkContext()
```

**O que faz:**

- Cria o contexto do Spark
- Spark = framework de processamento distribuído
- Gerencia cluster, paralelização, etc.

```scala
val glueContext = new GlueContext(sparkContext)
val spark = glueContext.getSparkSession
```

**O que faz:**

- `glueContext`: Extensão do Spark com features do AWS Glue
- `spark`: Interface principal para operações Spark SQL

```scala
Job.init(jobName, glueContext, args.asJava)
```

**O que faz:**

- Inicializa o job no AWS Glue
- Registra o job no sistema
- Habilita job bookmarking (rastreamento de progresso)

### 🔄 PROCESSAMENTO (Linhas 78-100)

```scala
try {
  processTransactions(
    spark,
    s3Bucket,
    year,
    month,
    day,
    dynamoDBTable,
    openSearchEndpoint,
    openSearchIndex,
    awsRegion
  )
```

**O que faz:**

- Chama a função principal de processamento
- Passa todos os parâmetros necessários
- Dentro de um `try-catch` para tratamento de erros

```scala
Job.commit()
logger.info("Job completed successfully")
```

**O que faz:**

- **IMPORTANTE**: Marca o job como concluído com sucesso
- Sem isso, o Glue considera o job como "ainda rodando"
- Loga mensagem de sucesso

```scala
} catch {
  case e: Exception =>
    logger.error("Job failed with exception", e)
    throw e
```

**O que faz:**

- Captura qualquer erro que ocorrer
- Loga o erro com stack trace completo
- Re-lança a exceção (para o Glue marcar como falha)

```scala
} finally {
  spark.stop()
}
```

**O que faz:**

- **SEMPRE** executado (mesmo com erro)
- Para o Spark gracefully
- Libera recursos (memória, conexões, etc.)

---

## 🔧 MÉTODO PROCESSTRANSACTIONS (Linhas 107-202)

```scala
def processTransactions(
  spark: SparkSession,
  s3Bucket: String,
  year: String,
  month: String,
  day: String,
  dynamoDBTable: String,
  openSearchEndpoint: String,
  openSearchIndex: String,
  awsRegion: String
): Unit = {
```

**O que é:**

- **Coração do processamento**
- Executa todo o pipeline ETL

### 📖 LEITURA DO S3 (Linhas 119-133)

```scala
import spark.implicits._
```

**O que faz:**

- Importa conversões implícitas do Spark
- Permite usar `.as[Transaction]` para type-safety

```scala
val s3Path = s"s3://$s3Bucket/transactions/year=$year/month=$month/day=$day/"
```

**O que faz:**

- Monta o caminho S3 particionado
- Exemplo: `s3://financial-transactions-dev-160885283918/transactions/year=2024/month=02/day=15/`
- Lê apenas os dados da data especificada (eficiente!)

```scala
val transactionsDF = spark.read
  .option("inferSchema", "true")
  .option("timestampFormat", "yyyy-MM-dd'T'HH:mm:ss'Z'")
  .json(s3Path)
```

**O que faz:**

- **Lê arquivos JSON do S3**
- `inferSchema`: Detecta automaticamente tipos de dados
- `timestampFormat`: Define formato de data/hora
- `json(s3Path)`: Lê todos os JSONs do caminho
- Retorna um `DataFrame` (estrutura tabular)

```scala
val transactions: Dataset[Transaction] = transactionsDF.as[Transaction]
```

**O que faz:**

- Converte `DataFrame` → `Dataset[Transaction]`
- `Dataset` é tipado (type-safe)
- Garante que os dados têm a estrutura esperada
- Compila apenas se os tipos baterem

```scala
val transactionCount = transactions.count()
logger.info(s"Loaded $transactionCount transactions")
```

**O que faz:**

- Conta quantas transações foram lidas
- `.count()` = ação que dispara execução
- Loga o número para monitoramento

```scala
if (transactionCount == 0) {
  logger.warn("No transactions found for the specified date")
  return
}
```

**O que faz:**

- Verifica se há dados
- Se não houver, loga warning e sai
- Evita processamento desnecessário

### 🔍 PREPARAÇÃO OPENSEARCH (Linhas 145-147)

```scala
val openSearchSink = OpenSearchSink(openSearchEndpoint, openSearchIndex)
openSearchSink.createIndexIfNotExists()
```

**O que faz:**

- Cria instância do sink OpenSearch
- Garante que o índice existe (se não, cria)
- Define schema/mapping dos dados

### 💎 ENRIQUECIMENTO (Linhas 149-177)

```scala
val enrichedTransactions = transactions.rdd.mapPartitions { partition =>
```

**O que faz:**

- **核心 DO PROCESSAMENTO**
- `.rdd`: Converte Dataset → RDD (Resilient Distributed Dataset)
- `mapPartitions`: Processa dados partição por partição
- Cada partição roda em um executor diferente (paralelização)

**Por que mapPartitions?**

- Mais eficiente que `.map` (processa linha por linha)
- Cria **uma** conexão DynamoDB por partição (não por linha)
- Reutiliza recursos (conexões, clients, etc.)

```scala
logger.info("Processing partition...")
val enricher = DynamoDBEnricher(dynamoDBTable, awsRegion)
```

**O que faz:**

- Cria **UM** enricher por partição
- Enricher = gerencia conexão com DynamoDB
- Reutilizado para todas as transações da partição

```scala
try {
  partition.grouped(EnrichmentChunkSize).flatMap { chunk =>
```

**O que faz:**

- Divide a partição em **chunks de 1000**
- `grouped(1000)`: Cria grupos de 1000 transações
- `flatMap`: Processa cada chunk e concatena resultados

**Por que chunks?**

- Evita carregar partição inteira na memória
- Partição pode ter milhões de linhas → OOM
- Chunks de 1000 = seguro e eficiente

```scala
if (chunk.isEmpty) {
  Iterator.empty
} else {
  val uniqueAccountIds = chunk.map(_.numero_unico_conta).toSet
```

**O que faz:**

- Se chunk vazio, retorna iterador vazio
- Extrai IDs únicos de contas do chunk
- `.toSet` remove duplicatas
- Exemplo: chunk de 1000 pode ter 800 contas únicas

```scala
val customerDataMap = enricher.batchGetCustomerData(uniqueAccountIds)
```

**O que faz:**

- **BUSCA DADOS NO DYNAMODB**
- Batch-get: busca até 100 itens por request
- Se 800 IDs → faz 8 requests (100 cada)
- Retorna: Map[accountId → CustomerData]

```scala
chunk.map { transaction =>
  val customerData = customerDataMap.get(transaction.numero_unico_conta)
  EnrichedTransaction.fromTransactionAndCustomer(transaction, customerData)
}.iterator
```

**O que faz:**

- Para cada transação do chunk:
  1. Busca dados do cliente no Map
  2. Mescla transação + cliente
  3. Cria `EnrichedTransaction`
- Retorna iterador com transações enriquecidas

```scala
} catch {
  case e: Exception =>
    logger.error("Error processing partition", e)
    Iterator.empty
```

**O que faz:**

- Se erro em uma partição:
  - Loga o erro
  - Retorna iterador vazio (não para todo o job)
  - Outras partições continuam processando

```scala
} finally {
  enricher.close()
}
```

**O que faz:**

- **SEMPRE** fecha o enricher
- Fecha conexões com DynamoDB
- Libera recursos

### 💾 GRAVAÇÃO NO OPENSEARCH (Linhas 179-197)

```scala
enrichedTransactions.foreachPartition { partition =>
```

**O que faz:**

- Processa cada partição de transações enriquecidas
- `foreachPartition`: Ação que dispara execução
- Cada partição processa independentemente

```scala
logger.info("Writing partition to OpenSearch...")
val sink = OpenSearchSink(openSearchEndpoint, openSearchIndex)
```

**O que faz:**

- Cria **UM** sink por partição
- Sink = gerencia conexão com OpenSearch
- Reutilizado para todos os documentos da partição

```scala
try {
  val indexed = sink.writeBulk(partition)
  logger.info(s"Successfully indexed $indexed documents from partition")
```

**O que faz:**

- Grava documentos em **bulk** (lote)
- Muito mais eficiente que um por vez
- Retorna quantos foram indexados

```scala
} catch {
  case e: Exception =>
    logger.error("Error writing partition to OpenSearch", e)
```

**O que faz:**

- Se erro ao gravar partição:
  - Loga o erro
  - Não para outras partições

```scala
} finally {
  sink.close()
}
```

**O que faz:**

- Fecha conexão com OpenSearch
- Libera recursos

### 📊 ESTATÍSTICAS (Linhas 199-202)

```scala
logger.info("Transaction processing completed")

val enrichedCount = enrichedTransactions.count()
logger.info(s"Total enriched transactions: $enrichedCount")
logger.info(s"Enrichment rate: ${(enrichedCount.toDouble / transactionCount * 100).formatted("%.2f")}%")
```

**O que faz:**

- Conta total de transações enriquecidas
- Calcula taxa de enriquecimento (%)
- Exemplo: 950 de 1000 = 95%
- Ajuda a identificar problemas (muitas sem match)

---

# 🗄️ ARQUIVO 2: DynamoDBEnricher.scala

## 📍 Onde começa: **Linha 1**

### 🎯 Propósito: **Buscar dados de clientes no DynamoDB de forma eficiente**

---

## 📦 IMPORTS (Linhas 1-11)

```scala
package enrichment
```

**O que faz:**

- Define namespace/pacote
- Organiza código em módulos

```scala
import com.amazonaws.services.dynamodbv2.AmazonDynamoDB
import com.amazonaws.services.dynamodbv2.AmazonDynamoDBClientBuilder
import com.amazonaws.services.dynamodbv2.model._
```

**O que faz:**

- Importa SDK do DynamoDB da AWS
- `AmazonDynamoDB`: Interface do client
- `AmazonDynamoDBClientBuilder`: Cria o client
- `model._`: Importa todas as classes de modelo

---

## 🏗️ CLASSE DYNAMODBENRICHER (Linhas 17-170)

```scala
class DynamoDBEnricher(tableName: String, region: String) extends Serializable {
```

**O que é:**

- Classe que encapsula lógica de enriquecimento
- `tableName`: Nome da tabela DynamoDB
- `region`: Região AWS (us-east-2)
- `Serializable`: Pode ser enviada para executores remotos

```scala
@transient private lazy val logger = LoggerFactory.getLogger(getClass)
```

**O que faz:**

- `@transient`: Não serializa o logger
- `lazy`: Só cria quando usado
- Cada executor terá seu próprio logger

```scala
@transient private lazy val dynamoDBClient: AmazonDynamoDB = {
  AmazonDynamoDBClientBuilder
    .standard()
    .withRegion(region)
    .build()
}
```

**O que faz:**

- Cria client do DynamoDB
- `@transient`: Não serializa (criado em cada executor)
- `lazy`: Só cria quando necessário
- Configurado para a região especificada

### 🔍 BATCH-GET (Linhas 32-48)

```scala
def batchGetCustomerData(accountIds: Set[String]): Map[String, CustomerData] = {
```

**O que faz:**

- **Método principal**: busca dados de vários clientes
- Recebe: Set de IDs de conta
- Retorna: Map[ID → CustomerData]

```scala
if (accountIds.isEmpty) {
  logger.warn("No account IDs provided for batch-get")
  return Map.empty
}
```

**O que faz:**

- Valida entrada
- Se vazio, retorna Map vazio
- Evita chamadas desnecessárias ao DynamoDB

```scala
logger.info(s"Fetching customer data for ${accountIds.size} unique accounts")

val batches = accountIds.grouped(100).toList
```

**O que faz:**

- Loga quantos IDs vai buscar
- **Divide em lotes de 100**
- DynamoDB limita batch-get a 100 itens
- Exemplo: 850 IDs → 9 batches (8×100 + 1×50)

```scala
batches.flatMap { batch =>
  batchGetWithRetry(batch, maxRetries = 3)
}.toMap
```

**O que faz:**

- Processa cada batch
- `flatMap`: Concatena resultados
- Usa retry (3 tentativas)
- Converte lista de pares em Map

### 🔄 RETRY LOGIC (Linhas 53-78)

```scala
private def batchGetWithRetry(
  accountIds: Set[String],
  maxRetries: Int
): Map[String, CustomerData] = {
```

**O que faz:**

- Executa batch-get com retry
- Se falhar, tenta novamente
- Até 3 tentativas

```scala
def attempt(retriesLeft: Int): Map[String, CustomerData] = {
  Try {
    performBatchGet(accountIds)
  } match {
```

**O que faz:**

- Função recursiva interna
- `Try`: Captura exceções
- `match`: Trata Success ou Failure

```scala
case Success(result) =>
  logger.info(s"Successfully fetched ${result.size} customer records")
  result
```

**O que faz:**

- Se sucesso, retorna resultado
- Loga quantos registros foram buscados

```scala
case Failure(exception) if retriesLeft > 0 =>
  logger.warn(s"Batch-get failed, retrying... (${retriesLeft} retries left)", exception)
  Thread.sleep(1000 * (maxRetries - retriesLeft + 1))
  attempt(retriesLeft - 1)
```

**O que faz:**

- Se falhou E tem retries restantes:
  - Loga warning
  - **Backoff exponencial**: espera 1s, 2s, 3s...
  - Tenta novamente (recursão)

```scala
case Failure(exception) =>
  logger.error("Batch-get failed after all retries", exception)
  Map.empty
```

**O que faz:**

- Se esgotou retries:
  - Loga erro
  - Retorna Map vazio (não para o job)

### 📡 BATCH-GET REQUEST (Linhas 83-110)

```scala
private def performBatchGet(accountIds: Set[String]): Map[String, CustomerData] = {
```

**O que faz:**

- Executa a chamada real ao DynamoDB

```scala
val keys = accountIds.map { accountId =>
  Map("numero_unico_conta" -> new AttributeValue().withS(accountId)).asJava
}.toList.asJava
```

**O que faz:**

- Converte IDs em formato DynamoDB
- `AttributeValue().withS()`: String value
- `.asJava`: Converte para coleção Java (SDK requer)

```scala
val keysAndAttributes = new KeysAndAttributes()
  .withKeys(keys)
  .withConsistentRead(false)
```

**O que faz:**

- Cria objeto com as chaves a buscar
- `consistentRead(false)`: Leitura **eventually consistent**
  - Mais barato
  - Mais rápido
  - OK para este caso (dados não mudam muito)

```scala
val requestItems = Map(tableName -> keysAndAttributes).asJava

val request = new BatchGetItemRequest()
  .withRequestItems(requestItems)

val result = dynamoDBClient.batchGetItem(request)
```

**O que faz:**

- Monta requisição batch-get
- Executa chamada ao DynamoDB
- Retorna resultado

### ⚠️ UNPROCESSED KEYS (Linhas 112-127)

```scala
var unprocessedKeys = result.getUnprocessedKeys
var allItems = result.getResponses.get(tableName).asScala.toList
```

**O que faz:**

- Extrai resultados
- `unprocessedKeys`: Chaves que não foram processadas
  - Ocorre quando DynamoDB está sob throttling
  - Ou quando batch é muito grande

```scala
var retryCount = 0
while (!unprocessedKeys.isEmpty && retryCount < 5) {
  logger.warn(s"Found ${unprocessedKeys.get(tableName).getKeys.size()} unprocessed keys, retrying...")
  Thread.sleep(Math.pow(2, retryCount).toLong * 100)
```

**O que faz:**

- Loop para processar chaves não processadas
- Até 5 tentativas
- **Backoff exponencial**: 100ms, 200ms, 400ms, 800ms, 1600ms

```scala
val retryRequest = new BatchGetItemRequest().withRequestItems(unprocessedKeys)
val retryResult = dynamoDBClient.batchGetItem(retryRequest)

allItems = allItems ++ retryResult.getResponses.get(tableName).asScala.toList
unprocessedKeys = retryResult.getUnprocessedKeys
retryCount += 1
```

**O que faz:**

- Tenta buscar chaves não processadas
- Adiciona resultados aos anteriores
- Atualiza unprocessedKeys para próxima iteração

### 🔄 PARSING (Linhas 129-135)

```scala
allItems.flatMap { item =>
  parseCustomerData(item.asScala.toMap)
}.map { customer =>
  customer.numero_unico_conta -> customer
}.toMap
```

**O que faz:**

- Converte items DynamoDB → CustomerData
- `flatMap`: Remove Nones (parse failures)
- Cria pares (ID → CustomerData)
- Converte em Map

### 🔧 PARSE CUSTOMER DATA (Linhas 140-163)

```scala
private def parseCustomerData(item: Map[String, AttributeValue]): Option[CustomerData] = {
  Try {
    CustomerData(
      numero_unico_conta = item("numero_unico_conta").getS,
      nome_titular_conta = item("nome_titular_conta").getS,
      data_nascimento_titular_conta = new Timestamp(
        java.time.Instant.parse(item("data_nascimento_titular_conta").getS).toEpochMilli
      ),
      zipCode = item("zip-code").getS,
      data_criacao_registro = item("data_criacao_registro").getS
    )
  } match {
```

**O que faz:**

- Converte item DynamoDB em case class
- `.getS`: Extrai String value
- Parse de data/timestamp
- `Try`: Captura erros de parsing

```scala
case Success(customer) => Some(customer)
case Failure(exception) =>
  logger.error(s"Failed to parse customer data: ${item.get("numero_unico_conta")}", exception)
  None
```

**O que faz:**

- Se sucesso: retorna Some(customer)
- Se erro: loga e retorna None
- None será removido pelo flatMap

---

# 📊 ARQUIVO 3: Transaction.scala

## 📍 Onde começa: **Linha 1**

### 🎯 Propósito: **Definir estruturas de dados (modelos)**

---

## 📦 CASE CLASSES (Linhas 1-68)

```scala
package models

import java.sql.Timestamp
```

**O que faz:**

- Define package
- Importa Timestamp para datas

### Transaction (Linhas 9-16)

```scala
case class Transaction(
  codigo_lancamento: String,
  numero_unico_conta: String,
  valor_total_transacao: Double,
  data_completa_transacao: Timestamp,
  tipo_transacao: String,
  tipo_produto_transacao: String
)
```

**O que é:**

- Modelo de transação do S3
- **snake_case**: Mesmo formato do JSON
- Spark mapeia automaticamente

**Campos:**

- `codigo_lancamento`: ID único da transação
- `numero_unico_conta`: ID da conta
- `valor_total_transacao`: Valor em R$
- `data_completa_transacao`: Timestamp da transação
- `tipo_transacao`: CREDITO ou DEBITO
- `tipo_produto_transacao`: PIX, TED, DOC, etc.

### CustomerData (Linhas 21-27)

```scala
case class CustomerData(
  numero_unico_conta: String,
  nome_titular_conta: String,
  data_nascimento_titular_conta: Timestamp,
  zipCode: String,
  data_criacao_registro: String
)
```

**O que é:**

- Modelo de cliente do DynamoDB
- Mix de snake_case e camelCase (legacy)

**Campos:**

- `numero_unico_conta`: ID da conta (chave)
- `nome_titular_conta`: Nome do cliente
- `data_nascimento_titular_conta`: Data de nascimento
- `zipCode`: CEP
- `data_criacao_registro`: Quando foi criado

### EnrichedTransaction (Linhas 32-42)

```scala
case class EnrichedTransaction(
  codigoLancamento: String,
  numeroUnicoConta: String,
  valorTotalTransacao: Double,
  dataCompletaTransacao: Timestamp,
  tipoTransacao: String,
  tipoProdutoTransacao: String,
  nomeTitularConta: Option[String],
  dataNascimentoTitularConta: Option[Timestamp],
  zipCode: Option[String]
)
```

**O que é:**

- Modelo final para OpenSearch
- **camelCase**: Requisito do projeto
- Campos do cliente são `Option` (podem não existir)

**Por que Option?**

- Cliente pode não estar no DynamoDB
- `Option[String]` = Some("João") ou None
- Evita null pointer exceptions

### Factory Method (Linhas 44-68)

```scala
object EnrichedTransaction {
  def fromTransactionAndCustomer(
    transaction: Transaction,
    customerDataOpt: Option[CustomerData]
  ): EnrichedTransaction = {
    EnrichedTransaction(
      codigoLancamento = transaction.codigo_lancamento,
      numeroUnicoConta = transaction.numero_unico_conta,
      valorTotalTransacao = transaction.valor_total_transacao,
      dataCompletaTransacao = transaction.data_completa_transacao,
      tipoTransacao = transaction.tipo_transacao,
      tipoProdutoTransacao = transaction.tipo_produto_transacao,
      nomeTitularConta = customerDataOpt.map(_.nome_titular_conta),
      dataNascimentoTitularConta = customerDataOpt.map(_.data_nascimento_titular_conta),
      zipCode = customerDataOpt.map(_.zipCode)
    )
  }
}
```

**O que faz:**

- Cria EnrichedTransaction mesclando dados
- Converte snake_case → camelCase
- `customerDataOpt.map(_.campo)`:
  - Se Some(customer): Some(customer.campo)
  - Se None: None

---

# 📤 ARQUIVO 4: OpenSearchSink.scala

## 📍 Onde começa: **Linha 1**

### 🎯 Propósito: **Gravar transações enriquecidas no OpenSearch**

---

## 📦 IMPORTS (Linhas 1-15)

```scala
package sink

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.scala.DefaultScalaModule
```

**O que faz:**

- Jackson: Biblioteca para JSON
- Converte case classes → JSON

```scala
import org.opensearch.client.{RequestOptions, RestClient, RestHighLevelClient}
import org.opensearch.action.bulk.{BulkRequest, BulkResponse}
import org.opensearch.action.index.IndexRequest
```

**O que faz:**

- Cliente OpenSearch
- Classes para bulk indexing
- Classes para requisições

---

## 🏗️ CLASSE OPENSEARCHSINK (Linhas 22-218)

```scala
class OpenSearchSink(
  endpoint: String,
  indexName: String,
  batchSize: Int = 1000
) extends Serializable {
```

**O que é:**

- Classe para gravar no OpenSearch
- `endpoint`: URL do cluster
- `indexName`: Nome do índice
- `batchSize`: Quantos docs por bulk (padrão 1000)

### 🔧 JACKSON MAPPER (Linhas 28-32)

```scala
@transient private lazy val objectMapper: ObjectMapper = {
  val mapper = new ObjectMapper()
  mapper.registerModule(DefaultScalaModule)
  mapper
}
```

**O que faz:**

- Cria mapper JSON
- `DefaultScalaModule`: Suporte para case classes Scala
- Converte EnrichedTransaction → JSON automaticamente

### 🌐 OPENSEARCH CLIENT (Linhas 35-42)

```scala
@transient private lazy val client: RestHighLevelClient = {
  val httpHost = HttpHost.create(s"https://$endpoint")

  val restClientBuilder = RestClient.builder(httpHost)

  new RestHighLevelClient(restClientBuilder)
}
```

**O que faz:**

- Cria cliente OpenSearch
- Usa HTTPS
- `@transient lazy`: Criado em cada executor

### 💾 WRITE BULK (Linhas 49-63)

```scala
def writeBulk(transactions: Iterator[EnrichedTransaction]): Int = {
  var totalIndexed = 0

  transactions.grouped(batchSize).foreach { batch =>
    val indexed = indexBatch(batch)
    totalIndexed += indexed
    logger.info(s"Indexed $indexed documents (total: $totalIndexed)")
  }

  totalIndexed
}
```

**O que faz:**

- Grava transações em lotes
- Divide em batches de 1000
- Retorna total indexado
- Loga progresso

### 📊 INDEX BATCH (Linhas 68-108)

```scala
private def indexBatch(batch: Seq[EnrichedTransaction]): Int = {
  if (batch.isEmpty) {
    return 0
  }

  val bulkRequest = new BulkRequest()
```

**O que faz:**

- Indexa um batch de documentos
- Cria requisição bulk vazia

```scala
batch.foreach { transaction =>
  try {
    val jsonString = objectMapper.writeValueAsString(transaction)
```

**O que faz:**

- Para cada transação:
  - Converte para JSON string
  - Usa Jackson mapper

```scala
val indexRequest = new IndexRequest(indexName)
  .id(transaction.codigoLancamento)
  .source(jsonString, XContentType.JSON)

bulkRequest.add(indexRequest)
```

**O que faz:**

- Cria request de índice
- Define ID do documento (código lançamento)
- Usa JSON como source
- Adiciona ao bulk request

```scala
} catch {
  case e: Exception =>
    logger.error(s"Failed to serialize transaction: ${transaction.codigoLancamento}", e)
}
```

**O que faz:**

- Se erro ao serializar:
  - Loga erro
  - Continua com próximo documento
  - Não para o batch inteiro

```scala
executeBulkWithRetry(bulkRequest, maxRetries = 3) match {
  case Success(response) =>
    if (response.hasFailures) {
      logger.warn(s"Bulk indexing had failures: ${response.buildFailureMessage()}")
      batch.size - response.getItems.count(_.isFailed)
    } else {
      batch.size
    }
```

**O que faz:**

- Executa bulk request com retry
- Se sucesso mas com falhas parciais:
  - Loga falhas
  - Retorna quantos foram indexados
- Se sucesso total: retorna tamanho do batch

### 🔄 RETRY LOGIC (Linhas 118-148)

```scala
private def executeBulkWithRetry(
  bulkRequest: BulkRequest,
  maxRetries: Int
): Try[BulkResponse] = {

  def attempt(retriesLeft: Int): Try[BulkResponse] = {
    Try {
      client.bulk(bulkRequest, RequestOptions.DEFAULT)
    } match {
      case success @ Success(_) =>
        success

      case Failure(exception) if retriesLeft > 0 =>
        logger.warn(s"Bulk request failed, retrying... (${retriesLeft} retries left)", exception)
        Thread.sleep(1000 * (maxRetries - retriesLeft + 1))
        attempt(retriesLeft - 1)

      case failure @ Failure(exception) =>
        logger.error("Bulk request failed after all retries", exception)
        failure
    }
  }

  attempt(maxRetries)
}
```

**O que faz:**

- Tenta enviar bulk ao OpenSearch
- Se falhar: retry com backoff exponencial
- Até 3 tentativas
- Similar à lógica do DynamoDB

### 🏗️ CREATE INDEX (Linhas 153-194)

```scala
def createIndexIfNotExists(): Unit = {
  Try {
    val indexExists = client.indices().exists(
      new org.opensearch.client.indices.GetIndexRequest(indexName),
      RequestOptions.DEFAULT
    )
```

**O que faz:**

- Verifica se índice existe
- Se não, cria com mapping

```scala
if (!indexExists) {
  logger.info(s"Creating index: $indexName")

  val mapping = """
  {
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
    },
    "settings": {
      "number_of_shards": 3,
      "number_of_replicas": 1,
      "refresh_interval": "30s"
    }
  }
  """
```

**O que faz:**

- Define schema do índice
- **keyword**: Não analisado (exato)
- **text**: Analisado (busca full-text)
- **double**: Números decimais
- **date**: Timestamps
- **3 shards**: Distribuição de dados
- **1 replica**: Backup
- **refresh 30s**: Atualiza índice a cada 30s

```scala
val createIndexRequest = new org.opensearch.client.indices.CreateIndexRequest(indexName)
  .source(mapping, XContentType.JSON)

client.indices().create(createIndexRequest, RequestOptions.DEFAULT)
```

**O que faz:**

- Cria índice com o mapping definido
- Loga sucesso

---

## 🎯 FLUXO COMPLETO RESUMIDO

```
1. MAIN
   ├─ Parse argumentos (data, buckets, etc.)
   ├─ Inicializa Spark/Glue
   └─ Chama processTransactions()

2. PROCESSTRANSACTIONS
   ├─ Lê JSONs do S3 → Dataset[Transaction]
   ├─ Cria OpenSearch sink e índice
   ├─ mapPartitions (por partição):
   │  ├─ Cria DynamoDBEnricher
   │  ├─ Divide em chunks de 1000
   │  ├─ Para cada chunk:
   │  │  ├─ Extrai IDs únicos
   │  │  ├─ batchGetCustomerData(IDs) → Map[ID → Customer]
   │  │  └─ Mescla transação + cliente
   │  └─ Fecha enricher
   └─ foreachPartition (gravação):
      ├─ Cria OpenSearchSink
      ├─ writeBulk(transações)
      │  ├─ Divide em batches de 1000
      │  ├─ Para cada batch:
      │  │  ├─ Cria BulkRequest
      │  │  ├─ Adiciona IndexRequests
      │  │  └─ Envia com retry
      │  └─ Retorna total indexado
      └─ Fecha sink

3. DYNAMODBENRICHER
   ├─ batchGetCustomerData(IDs)
   ├─ Divide em batches de 100 (limite DynamoDB)
   ├─ Para cada batch:
   │  ├─ performBatchGet() com retry
   │  ├─ Trata unprocessed keys
   │  └─ Parse de items → CustomerData
   └─ Retorna Map[ID → CustomerData]

4. OPENSEARCHSINK
   ├─ createIndexIfNotExists() (uma vez)
   ├─ writeBulk(transações)
   ├─ indexBatch() por lote de 1000
   ├─ Converte para JSON
   ├─ Envia BulkRequest com retry
   └─ Retorna quantos foram indexados
```

---

## 🔑 CONCEITOS CHAVE

### MapPartitions vs Map

- **map**: Processa linha por linha (ineficiente)
- **mapPartitions**: Processa partição inteira (eficiente)
  - Uma conexão por partição (não por linha)
  - Reutiliza recursos

### Batch Processing

- **DynamoDB**: Máx 100 itens/request
- **OpenSearch**: Recomendado 1000 docs/bulk
- **Chunks**: Evita OOM em partições grandes

### Error Handling

- **Try/Catch**: Captura erros
- **Retry com Backoff**: Tenta novamente com espera
- **Graceful Degradation**: Continua mesmo com erros parciais

### Lazy Initialization

- `@transient lazy val`: Cria quando necessário
- Evita serialização
- Cada executor tem sua instância

### Type Safety

- **Dataset[T]**: Tipado em compile-time
- **Case Classes**: Estruturas imutáveis
- **Option[T]**: Valores opcionais (sem null)

---

## 📊 PERFORMANCE

### Paralelização

- Spark divide dados em **partições**
- Cada partição processa em **executor diferente**
- Processamento **paralelo e distribuído**

### Batch Operations

- **100 IDs** buscados por request (vs 1)
- **1000 docs** indexados por bulk (vs 1)
- **100x mais eficiente**

### Reuso de Conexões

- **Uma** conexão DynamoDB por partição
- **Uma** conexão OpenSearch por partição
- Não cria/fecha a cada linha

---

## 🎓 CONCLUSÃO

O código implementa um **ETL pipeline eficiente** que:

1. ✅ Lê dados particionados do S3
2. ✅ Enriquece com DynamoDB (batch-get)
3. ✅ Grava no OpenSearch (bulk indexing)
4. ✅ Trata erros graciosamente
5. ✅ Usa retry e backoff
6. ✅ Processa em paralelo (Spark)
7. ✅ É type-safe (Scala)
8. ✅ É eficiente (batching, reuso)

**Próximo passo:** Execute com `make run-glue`! 🚀
