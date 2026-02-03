import com.amazonaws.services.glue.GlueContext
import com.amazonaws.services.glue.util.{GlueArgParser, Job}
import enrichment.DynamoDBEnricher
import models.{EnrichedTransaction, Transaction}
import org.apache.spark.SparkContext
import org.apache.spark.sql.{Dataset, SparkSession}
import sink.OpenSearchSink
import org.slf4j.LoggerFactory

import scala.collection.JavaConverters._

/**
 * Job AWS Glue para processamento de transações financeiras
 *
 * Este job:
 * 1. Lê dados de transações do S3 (particionados por ano/mês/dia)
 * 2. Enriquece transações com dados de clientes do DynamoDB via batch-get
 * 3. Grava dados enriquecidos no OpenSearch em formato camelCase
 *
 * Características principais:
 * - Usa MapPartitions para processamento em lote eficiente
 * - Batch-get no DynamoDB (máx. 100 itens por requisição)
 * - Indexação em massa no OpenSearch
 * - Tratamento de erros e lógica de retry
 */
object FinancialTransactionProcessor {

  /** Tamanho do chunk por partição: evita carregar a partição inteira na memória (OOM em partições grandes). */
  private val EnrichmentChunkSize = 1000

  private val logger = LoggerFactory.getLogger(getClass)
  
  def main(sysArgs: Array[String]): Unit = {
    logger.info("Starting Financial Transaction Processor")
    
    // Analisa os argumentos
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
    
    val jobName = args("JOB_NAME")
    val year = args("year")
    val month = args("month")
    val day = args("day")
    val s3Bucket = args("s3_bucket")
    val dynamoDBTable = args("dynamodb_table")
    val openSearchEndpoint = args("opensearch_endpoint")
    val openSearchIndex = args("opensearch_index")
    val awsRegion = args("aws_region")
    
    logger.info(s"Job Parameters:")
    logger.info(s"  Job Name: $jobName")
    logger.info(s"  Date: $year-$month-$day")
    logger.info(s"  S3 Bucket: $s3Bucket")
    logger.info(s"  DynamoDB Table: $dynamoDBTable")
    logger.info(s"  OpenSearch Endpoint: $openSearchEndpoint")
    logger.info(s"  OpenSearch Index: $openSearchIndex")
    logger.info(s"  AWS Region: $awsRegion")
    
    // Inicializa contextos Spark e Glue
    val sparkContext = new SparkContext()
    val glueContext = new GlueContext(sparkContext)
    val spark = glueContext.getSparkSession
    
    // Inicializa o job
    Job.init(jobName, glueContext, args.asJava)
    
    try {
      // Processa as transações
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
      
      // Confirma o job
      Job.commit()
      logger.info("Job completed successfully")
      
    } catch {
      case e: Exception =>
        logger.error("Job failed with exception", e)
        throw e
    } finally {
      spark.stop()
    }
  }
  
  /**
   * Lógica principal de processamento
   */
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
    
    import spark.implicits._
    
    // Monta o caminho S3 para a partição de data específica
    val s3Path = s"s3://$s3Bucket/transactions/year=$year/month=$month/day=$day/"
    logger.info(s"Reading transactions from: $s3Path")
    
    // Lê arquivos JSON do S3
    val transactionsDF = spark.read
      .option("inferSchema", "true")
      .option("timestampFormat", "yyyy-MM-dd'T'HH:mm:ss'Z'")
      .json(s3Path)
    
    // Converte para Dataset para segurança de tipos
    val transactions: Dataset[Transaction] = transactionsDF.as[Transaction]
    
    val transactionCount = transactions.count()
    logger.info(s"Loaded $transactionCount transactions")
    
    if (transactionCount == 0) {
      logger.warn("No transactions found for the specified date")
      return
    }
    
    // Cria o sink OpenSearch e garante que o índice exista
    val openSearchSink = OpenSearchSink(openSearchEndpoint, openSearchIndex)
    openSearchSink.createIndexIfNotExists()
    
    // Processa transações usando mapPartitions: uma conexão/enricher por partição, dados em chunks
    val enrichedTransactions = transactions.rdd.mapPartitions { partition =>
      logger.info("Processing partition...")
      val enricher = DynamoDBEnricher(dynamoDBTable, awsRegion)

      try {
        // Processa a partição em chunks (Iterator) em vez de partition.toList.
        // Assim só há no máximo EnrichmentChunkSize registros na memória por vez, evitando OOM
        // em partições muito grandes. Cada chunk gera um batch-get ao DynamoDB.
        partition.grouped(EnrichmentChunkSize).flatMap { chunk =>
          if (chunk.isEmpty) {
            Iterator.empty
          } else {
            val uniqueAccountIds = chunk.map(_.numero_unico_conta).toSet
            val customerDataMap = enricher.batchGetCustomerData(uniqueAccountIds)
            chunk.map { transaction =>
              val customerData = customerDataMap.get(transaction.numero_unico_conta)
              EnrichedTransaction.fromTransactionAndCustomer(transaction, customerData)
            }.iterator
          }
        }
      } catch {
        case e: Exception =>
          logger.error("Error processing partition", e)
          Iterator.empty
      } finally {
        enricher.close()
      }
    }
    
    // Grava no OpenSearch usando foreachPartition para escritas em massa eficientes
    enrichedTransactions.foreachPartition { partition =>
      logger.info("Writing partition to OpenSearch...")
      
      val sink = OpenSearchSink(openSearchEndpoint, openSearchIndex)
      
      try {
        val indexed = sink.writeBulk(partition)
        logger.info(s"Successfully indexed $indexed documents from partition")
      } catch {
        case e: Exception =>
          logger.error("Error writing partition to OpenSearch", e)
      } finally {
        sink.close()
      }
    }
    
    logger.info("Transaction processing completed")
    
    // Registra estatísticas
    val enrichedCount = enrichedTransactions.count()
    logger.info(s"Total enriched transactions: $enrichedCount")
    logger.info(s"Enrichment rate: ${(enrichedCount.toDouble / transactionCount * 100).formatted("%.2f")}%")
  }
}
