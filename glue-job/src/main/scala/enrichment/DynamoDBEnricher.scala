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
 * Enricher DynamoDB que realiza operações batch-get
 * para recuperar dados de clientes das transações.
 */
class DynamoDBEnricher(tableName: String, region: String) extends Serializable {
  
  @transient private lazy val logger = LoggerFactory.getLogger(getClass)
  
  // Cliente DynamoDB é criado de forma lazy por executor
  @transient private lazy val dynamoDBClient: AmazonDynamoDB = {
    AmazonDynamoDBClientBuilder
      .standard()
      .withRegion(region)
      .build()
  }
  
  /**
   * Batch-get de dados de clientes no DynamoDB.
   * O DynamoDB permite no máximo 100 itens por requisição batch-get.
   *
   * @param accountIds Conjunto de IDs de conta únicos a buscar
   * @return Mapa de ID de conta para CustomerData
   */
  def batchGetCustomerData(accountIds: Set[String]): Map[String, CustomerData] = {
    if (accountIds.isEmpty) {
      logger.warn("No account IDs provided for batch-get")
      return Map.empty
    }
    
    logger.info(s"Fetching customer data for ${accountIds.size} unique accounts")
    
    // Divide em lotes de 100 (limite do DynamoDB)
    val batches = accountIds.grouped(100).toList
    
    batches.flatMap { batch =>
      batchGetWithRetry(batch, maxRetries = 3)
    }.toMap
  }
  
  /**
   * Executa batch-get com lógica de retry.
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
          Thread.sleep(1000 * (maxRetries - retriesLeft + 1)) // Backoff exponencial
          attempt(retriesLeft - 1)
          
        case Failure(exception) =>
          logger.error("Batch-get failed after all retries", exception)
          Map.empty
      }
    }
    
    attempt(maxRetries)
  }
  
  /**
   * Executa a operação batch-get em si.
   */
  private def performBatchGet(accountIds: Set[String]): Map[String, CustomerData] = {
    // Cria chaves para o batch-get
    val keys = accountIds.map { accountId =>
      Map("numero_unico_conta" -> new AttributeValue().withS(accountId)).asJava
    }.toList.asJava
    
    // Cria requisição batch-get
    val keysAndAttributes = new KeysAndAttributes()
      .withKeys(keys)
      .withConsistentRead(false) // Leituras eventualmente consistentes são mais baratas

    val requestItems = Map(tableName -> keysAndAttributes).asJava

    val request = new BatchGetItemRequest()
      .withRequestItems(requestItems)

    // Executa o batch-get
    val result = dynamoDBClient.batchGetItem(request)

    // Trata chaves não processadas (throttling)
    var unprocessedKeys = result.getUnprocessedKeys
    var allItems = result.getResponses.get(tableName).asScala.toList
    
    // Retenta chaves não processadas com backoff exponencial
    var retryCount = 0
    while (!unprocessedKeys.isEmpty && retryCount < 5) {
      logger.warn(s"Found ${unprocessedKeys.get(tableName).getKeys.size()} unprocessed keys, retrying...")
      Thread.sleep(Math.pow(2, retryCount).toLong * 100) // Backoff exponencial
      
      val retryRequest = new BatchGetItemRequest().withRequestItems(unprocessedKeys)
      val retryResult = dynamoDBClient.batchGetItem(retryRequest)
      
      allItems = allItems ++ retryResult.getResponses.get(tableName).asScala.toList
      unprocessedKeys = retryResult.getUnprocessedKeys
      retryCount += 1
    }
    
    // Converte itens DynamoDB em CustomerData
    allItems.flatMap { item =>
      parseCustomerData(item.asScala.toMap)
    }.map { customer =>
      customer.numero_unico_conta -> customer
    }.toMap
  }
  
  /**
   * Converte item DynamoDB em CustomerData.
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
   * Fecha o cliente DynamoDB (chamado ao final do processamento).
   */
  def close(): Unit = {
    if (dynamoDBClient != null) {
      dynamoDBClient.shutdown()
    }
  }
}

object DynamoDBEnricher {
  /**
   * Método fábrica para criar DynamoDBEnricher.
   */
  def apply(tableName: String, region: String): DynamoDBEnricher = {
    new DynamoDBEnricher(tableName, region)
  }
}
