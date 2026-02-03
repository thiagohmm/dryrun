package sink

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.scala.DefaultScalaModule
import models.EnrichedTransaction
import org.apache.http.HttpHost
import org.apache.http.auth.{AuthScope, UsernamePasswordCredentials}
import org.apache.http.impl.client.BasicCredentialsProvider
import org.opensearch.action.bulk.{BulkRequest, BulkResponse}
import org.opensearch.action.index.IndexRequest
import org.opensearch.client.{RequestOptions, RestClient, RestHighLevelClient}
import org.opensearch.common.xcontent.XContentType
import org.slf4j.LoggerFactory

import scala.collection.JavaConverters._
import scala.util.{Failure, Success, Try}

/**
 * Sink OpenSearch para gravação de transações enriquecidas.
 * Usa API bulk para indexação eficiente.
 */
class OpenSearchSink(
  endpoint: String,
  indexName: String,
  batchSize: Int = 1000
) extends Serializable {
  
  @transient private lazy val logger = LoggerFactory.getLogger(getClass)
  
  // Jackson ObjectMapper for JSON serialization
  @transient private lazy val objectMapper: ObjectMapper = {
    val mapper = new ObjectMapper()
    mapper.registerModule(DefaultScalaModule)
    mapper
  }
  
  // Cliente OpenSearch é criado de forma lazy por executor
  @transient private lazy val client: RestHighLevelClient = {
    val httpHost = HttpHost.create(s"https://$endpoint")
    
    val restClientBuilder = RestClient.builder(httpHost)
    
    new RestHighLevelClient(restClientBuilder)
  }
  
  /**
   * Grava transações enriquecidas no OpenSearch em massa.
   *
   * @param transactions Iterador de transações enriquecidas
   * @return Número de documentos indexados com sucesso
   */
  def writeBulk(transactions: Iterator[EnrichedTransaction]): Int = {
    var totalIndexed = 0

    // Processa em lotes
    transactions.grouped(batchSize).foreach { batch =>
      val indexed = indexBatch(batch)
      totalIndexed += indexed
      logger.info(s"Indexed $indexed documents (total: $totalIndexed)")
    }
    
    totalIndexed
  }
  
  /**
   * Indexa um lote de transações.
   */
  private def indexBatch(batch: Seq[EnrichedTransaction]): Int = {
    if (batch.isEmpty) {
      return 0
    }
    
    val bulkRequest = new BulkRequest()
    
    batch.foreach { transaction =>
      try {
        // Converte para JSON
        val jsonString = objectMapper.writeValueAsString(transaction)

        // Cria requisição de índice com ID do documento (codigo_lancamento)
        val indexRequest = new IndexRequest(indexName)
          .id(transaction.codigoLancamento)
          .source(jsonString, XContentType.JSON)
        
        bulkRequest.add(indexRequest)
      } catch {
        case e: Exception =>
          logger.error(s"Failed to serialize transaction: ${transaction.codigoLancamento}", e)
      }
    }
    
    // Execute bulk request with retry
    executeBulkWithRetry(bulkRequest, maxRetries = 3) match {
      case Success(response) =>
        if (response.hasFailures) {
          logger.warn(s"Bulk indexing had failures: ${response.buildFailureMessage()}")
          batch.size - response.getItems.count(_.isFailed)
        } else {
          batch.size
        }
      case Failure(exception) =>
        logger.error("Bulk indexing failed completely", exception)
        0
    }
  }
  
  /**
   * Envia uma requisição bulk ao OpenSearch com retentativas em caso de falha.
   *
   * Útil quando o cluster está sob carga, há throttling ou falhas transitórias de rede.
   * A cada falha, aguarda um tempo crescente (backoff) antes de tentar de novo.
   *
   * @param bulkRequest Requisição bulk contendo os documentos a indexar
   * @param maxRetries Número máximo de tentativas (ex.: 3 = 1 tentativa inicial + 3 retries)
   * @return Success(BulkResponse) em caso de sucesso, Failure(exception) após esgotar as tentativas
   */
  private def executeBulkWithRetry(
    bulkRequest: BulkRequest,
    maxRetries: Int
  ): Try[BulkResponse] = {

    /** Tenta enviar o bulk; se falhar e ainda houver retries, espera e tenta de novo. */
    def attempt(retriesLeft: Int): Try[BulkResponse] = {
      Try {
        client.bulk(bulkRequest, RequestOptions.DEFAULT)
      } match {
        case success @ Success(_) =>
          success

        case Failure(exception) if retriesLeft > 0 =>
          logger.warn(s"Bulk request failed, retrying... (${retriesLeft} retries left)", exception)
          // Backoff: espera 1s, 2s, 3s... antes de cada retry para não sobrecarregar o cluster
          Thread.sleep(1000 * (maxRetries - retriesLeft + 1))
          attempt(retriesLeft - 1)

        case failure @ Failure(exception) =>
          logger.error("Bulk request failed after all retries", exception)
          failure
      }
    }

    attempt(maxRetries)
  }
  
  /**
   * Cria o índice com mapeamento se não existir.
   */
  def createIndexIfNotExists(): Unit = {
    Try {
      val indexExists = client.indices().exists(
        new org.opensearch.client.indices.GetIndexRequest(indexName),
        RequestOptions.DEFAULT
      )
      
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
        
        val createIndexRequest = new org.opensearch.client.indices.CreateIndexRequest(indexName)
          .source(mapping, XContentType.JSON)
        
        client.indices().create(createIndexRequest, RequestOptions.DEFAULT)
        logger.info(s"Index created successfully: $indexName")
      } else {
        logger.info(s"Index already exists: $indexName")
      }
    } match {
      case Success(_) =>
        logger.info("Index check/creation completed")
      case Failure(exception) =>
        logger.error("Failed to create index", exception)
    }
  }
  
  /**
   * Close OpenSearch client
   */
  def close(): Unit = {
    if (client != null) {
      Try(client.close()) match {
        case Success(_) => logger.info("OpenSearch client closed")
        case Failure(e) => logger.error("Error closing OpenSearch client", e)
      }
    }
  }
}

object OpenSearchSink {
  /**
   * Método fábrica para criar OpenSearchSink.
   */
  def apply(endpoint: String, indexName: String, batchSize: Int = 1000): OpenSearchSink = {
    new OpenSearchSink(endpoint, indexName, batchSize)
  }
}
