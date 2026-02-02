package enrichment

import com.amazonaws.services.dynamodbv2.AmazonDynamoDB
import com.amazonaws.services.dynamodbv2.AmazonDynamoDBClientBuilder
import com.amazonaws.services.dynamodbv2.model._
import models.CustomerData
import org.slf4j.LoggerFactory

import java.sql.Timestamp
import scala.collection.JavaConverters._
import scala.util.{Failure, Success, Try}

/**
 * DynamoDB enricher that performs batch-get operations
 * to retrieve customer data for transactions
 */
class DynamoDBEnricher(tableName: String, region: String) extends Serializable {
  
  @transient private lazy val logger = LoggerFactory.getLogger(getClass)
  
  // DynamoDB client is created lazily per executor
  @transient private lazy val dynamoDBClient: AmazonDynamoDB = {
    AmazonDynamoDBClientBuilder
      .standard()
      .withRegion(region)
      .build()
  }
  
  /**
   * Batch-get customer data from DynamoDB
   * DynamoDB allows max 100 items per batch-get request
   * 
   * @param accountIds Set of unique account IDs to fetch
   * @return Map of account ID to CustomerData
   */
  def batchGetCustomerData(accountIds: Set[String]): Map[String, CustomerData] = {
    if (accountIds.isEmpty) {
      logger.warn("No account IDs provided for batch-get")
      return Map.empty
    }
    
    logger.info(s"Fetching customer data for ${accountIds.size} unique accounts")
    
    // Split into batches of 100 (DynamoDB limit)
    val batches = accountIds.grouped(100).toList
    
    batches.flatMap { batch =>
      batchGetWithRetry(batch, maxRetries = 3)
    }.toMap
  }
  
  /**
   * Perform batch-get with retry logic
   */
  private def batchGetWithRetry(
    accountIds: Set[String],
    maxRetries: Int
  ): Map[String, CustomerData] = {
    
    def attempt(retriesLeft: Int): Map[String, CustomerData] = {
      Try {
        performBatchGet(accountIds)
      } match {
        case Success(result) =>
          logger.info(s"Successfully fetched ${result.size} customer records")
          result
          
        case Failure(exception) if retriesLeft > 0 =>
          logger.warn(s"Batch-get failed, retrying... (${retriesLeft} retries left)", exception)
          Thread.sleep(1000 * (maxRetries - retriesLeft + 1)) // Exponential backoff
          attempt(retriesLeft - 1)
          
        case Failure(exception) =>
          logger.error("Batch-get failed after all retries", exception)
          Map.empty
      }
    }
    
    attempt(maxRetries)
  }
  
  /**
   * Perform the actual batch-get operation
   */
  private def performBatchGet(accountIds: Set[String]): Map[String, CustomerData] = {
    // Create keys for batch-get
    val keys = accountIds.map { accountId =>
      Map("numero_unico_conta" -> new AttributeValue().withS(accountId)).asJava
    }.toList.asJava
    
    // Create batch-get request
    val keysAndAttributes = new KeysAndAttributes()
      .withKeys(keys)
      .withConsistentRead(false) // Eventually consistent reads are cheaper
    
    val requestItems = Map(tableName -> keysAndAttributes).asJava
    
    val request = new BatchGetItemRequest()
      .withRequestItems(requestItems)
    
    // Execute batch-get
    val result = dynamoDBClient.batchGetItem(request)
    
    // Handle unprocessed keys (throttling)
    var unprocessedKeys = result.getUnprocessedKeys
    var allItems = result.getResponses.get(tableName).asScala.toList
    
    // Retry unprocessed keys with exponential backoff
    var retryCount = 0
    while (!unprocessedKeys.isEmpty && retryCount < 5) {
      logger.warn(s"Found ${unprocessedKeys.get(tableName).getKeys.size()} unprocessed keys, retrying...")
      Thread.sleep(Math.pow(2, retryCount).toLong * 100) // Exponential backoff
      
      val retryRequest = new BatchGetItemRequest().withRequestItems(unprocessedKeys)
      val retryResult = dynamoDBClient.batchGetItem(retryRequest)
      
      allItems = allItems ++ retryResult.getResponses.get(tableName).asScala.toList
      unprocessedKeys = retryResult.getUnprocessedKeys
      retryCount += 1
    }
    
    // Convert DynamoDB items to CustomerData
    allItems.flatMap { item =>
      parseCustomerData(item.asScala.toMap)
    }.map { customer =>
      customer.numero_unico_conta -> customer
    }.toMap
  }
  
  /**
   * Parse DynamoDB item to CustomerData
   */
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
      case Success(customer) => Some(customer)
      case Failure(exception) =>
        logger.error(s"Failed to parse customer data: ${item.get("numero_unico_conta")}", exception)
        None
    }
  }
  
  /**
   * Close DynamoDB client (called at the end of processing)
   */
  def close(): Unit = {
    if (dynamoDBClient != null) {
      dynamoDBClient.shutdown()
    }
  }
}

object DynamoDBEnricher {
  /**
   * Factory method to create DynamoDBEnricher
   */
  def apply(tableName: String, region: String): DynamoDBEnricher = {
    new DynamoDBEnricher(tableName, region)
  }
}
