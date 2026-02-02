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
 * AWS Glue Job for processing financial transactions
 * 
 * This job:
 * 1. Reads transaction data from S3 (partitioned by year/month/day)
 * 2. Enriches transactions with customer data from DynamoDB using batch-get
 * 3. Writes enriched data to OpenSearch in camelCase format
 * 
 * Key Features:
 * - Uses MapPartitions for efficient batch processing
 * - DynamoDB batch-get (max 100 items per request)
 * - Bulk indexing to OpenSearch
 * - Error handling and retry logic
 */
object FinancialTransactionProcessor {
  
  private val logger = LoggerFactory.getLogger(getClass)
  
  def main(sysArgs: Array[String]): Unit = {
    logger.info("Starting Financial Transaction Processor")
    
    // Parse arguments
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
    
    // Initialize Spark and Glue contexts
    val sparkContext = new SparkContext()
    val glueContext = new GlueContext(sparkContext)
    val spark = glueContext.getSparkSession
    
    // Initialize job
    Job.init(jobName, glueContext, args.asJava)
    
    try {
      // Process transactions
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
      
      // Commit job
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
   * Main processing logic
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
    
    // Construct S3 path for the specific date partition
    val s3Path = s"s3://$s3Bucket/transactions/year=$year/month=$month/day=$day/"
    logger.info(s"Reading transactions from: $s3Path")
    
    // Read JSON files from S3
    val transactionsDF = spark.read
      .option("inferSchema", "true")
      .option("timestampFormat", "yyyy-MM-dd'T'HH:mm:ss'Z'")
      .json(s3Path)
    
    // Convert to Dataset for type safety
    val transactions: Dataset[Transaction] = transactionsDF.as[Transaction]
    
    val transactionCount = transactions.count()
    logger.info(s"Loaded $transactionCount transactions")
    
    if (transactionCount == 0) {
      logger.warn("No transactions found for the specified date")
      return
    }
    
    // Create OpenSearch sink and ensure index exists
    val openSearchSink = OpenSearchSink(openSearchEndpoint, openSearchIndex)
    openSearchSink.createIndexIfNotExists()
    
    // Process transactions using mapPartitions for batch enrichment
    val enrichedTransactions = transactions.rdd.mapPartitions { partition =>
      logger.info("Processing partition...")
      
      // Create DynamoDB enricher for this partition
      val enricher = DynamoDBEnricher(dynamoDBTable, awsRegion)
      
      try {
        // Convert partition to list to allow multiple passes
        val transactionList = partition.toList
        
        if (transactionList.isEmpty) {
          logger.info("Empty partition, skipping")
          Iterator.empty
        } else {
          logger.info(s"Partition contains ${transactionList.size} transactions")
          
          // Extract unique account IDs from this partition
          val uniqueAccountIds = transactionList
            .map(_.numero_unico_conta)
            .toSet
          
          logger.info(s"Fetching customer data for ${uniqueAccountIds.size} unique accounts")
          
          // Batch-get customer data from DynamoDB
          val customerDataMap = enricher.batchGetCustomerData(uniqueAccountIds)
          
          logger.info(s"Retrieved ${customerDataMap.size} customer records")
          
          // Enrich each transaction with customer data
          val enriched = transactionList.map { transaction =>
            val customerData = customerDataMap.get(transaction.numero_unico_conta)
            EnrichedTransaction.fromTransactionAndCustomer(transaction, customerData)
          }
          
          logger.info(s"Enriched ${enriched.size} transactions in partition")
          
          enriched.iterator
        }
      } catch {
        case e: Exception =>
          logger.error("Error processing partition", e)
          Iterator.empty
      } finally {
        // Clean up enricher resources
        enricher.close()
      }
    }
    
    // Write to OpenSearch using foreachPartition for efficient bulk writes
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
    
    // Log statistics
    val enrichedCount = enrichedTransactions.count()
    logger.info(s"Total enriched transactions: $enrichedCount")
    logger.info(s"Enrichment rate: ${(enrichedCount.toDouble / transactionCount * 100).formatted("%.2f")}%")
  }
}
