package sink

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.scala.DefaultScalaModule
import models.EnrichedTransaction
import org.apache.http.HttpHost
import org.apache.http.auth.{AuthScope, UsernamePasswordCredentials}
import org.apache.http.impl.client.BasicCredentialsProvider
import org.apache.http.entity.{ContentType, StringEntity}
import org.apache.http.util.EntityUtils
import org.opensearch.client.{Request, RestClient}
import org.slf4j.LoggerFactory

import scala.util.{Failure, Success, Try}

class OpenSearchSink(
  endpoint: String,
  indexName: String,
  username: String = "admin",
  password: String = "Admin123!@#",
  batchSize: Int = 1000
) extends Serializable {
  
  @transient private lazy val logger = LoggerFactory.getLogger(getClass)
  
  @transient private lazy val objectMapper: ObjectMapper = {
    val mapper = new ObjectMapper()
    mapper.registerModule(DefaultScalaModule)
    mapper
  }
  
  @transient private lazy val client: RestClient = {
    val httpHost = HttpHost.create(s"https://$endpoint")
    
    // Configura autenticação básica
    val credentialsProvider = new BasicCredentialsProvider()
    credentialsProvider.setCredentials(
      AuthScope.ANY,
      new UsernamePasswordCredentials(username, password)
    )
    
    RestClient.builder(httpHost)
      .setHttpClientConfigCallback(httpClientBuilder => {
        httpClientBuilder.setDefaultCredentialsProvider(credentialsProvider)
      })
      .setRequestConfigCallback(requestConfigBuilder => {
        requestConfigBuilder
          .setConnectTimeout(5000)
          .setSocketTimeout(60000)
      })
      .build()
  }
  
  def createIndexIfNotExists(): Unit = {
    try {
      val checkRequest = new Request("HEAD", s"/$indexName")
      val checkResponse = client.performRequest(checkRequest)
      
      if (checkResponse.getStatusLine.getStatusCode == 404) {
        logger.info(s"Index $indexName does not exist, creating...")
        
        val createRequest = new Request("PUT", s"/$indexName")
        val mapping =
          s"""{
             |  "mappings": {
             |    "properties": {
             |      "codigoLancamento": { "type": "keyword" },
             |      "numeroUnicoConta": { "type": "keyword" },
             |      "valorTotalTransacao": { "type": "double" },
             |      "dataCompletaTransacao": { "type": "date" },
             |      "tipoTransacao": { "type": "keyword" },
             |      "tipoProdutoTransacao": { "type": "keyword" },
             |      "nomeTitularConta": { "type": "text" },
             |      "dataNascimentoTitularConta": { "type": "date" },
             |      "zipCode": { "type": "keyword" }
             |    }
             |  }
             |}""".stripMargin
        
        createRequest.setEntity(new StringEntity(mapping, ContentType.APPLICATION_JSON))
        client.performRequest(createRequest)
        
        logger.info(s"Index $indexName created successfully")
      } else {
        logger.info(s"Index $indexName already exists")
      }
    } catch {
      case e: Exception =>
        logger.error(s"Error checking/creating index $indexName", e)
        throw e
    }
  }
  
  def writeBulk(transactions: Iterator[EnrichedTransaction]): Int = {
    var totalIndexed = 0

    transactions.grouped(batchSize).foreach { batch =>
      val indexed = indexBatch(batch)
      totalIndexed += indexed
      logger.info(s"Indexed $indexed documents (total: $totalIndexed)")
    }
    
    totalIndexed
  }
  
  private def indexBatch(batch: Seq[EnrichedTransaction]): Int = {
    if (batch.isEmpty) {
      return 0
    }
    
    Try {
      val bulkBody = new StringBuilder()
      
      batch.foreach { transaction =>
        val actionMetadata = s"""{"index":{"_index":"$indexName","_id":"${transaction.codigoLancamento}"}}"""
        bulkBody.append(actionMetadata).append("\n")
        
        val jsonDoc = objectMapper.writeValueAsString(transaction)
        bulkBody.append(jsonDoc).append("\n")
      }
      
      val bulkRequest = new Request("POST", "/_bulk")
      bulkRequest.setEntity(new StringEntity(bulkBody.toString(), ContentType.APPLICATION_JSON))
      
      val response = client.performRequest(bulkRequest)
      val statusCode = response.getStatusLine.getStatusCode
      
      if (statusCode == 200 || statusCode == 201) {
        val responseBody = EntityUtils.toString(response.getEntity)
        val responseJson = objectMapper.readTree(responseBody)
        
        val errors = responseJson.get("errors").asBoolean()
        if (errors) {
          logger.warn(s"Bulk request had errors. Check OpenSearch logs.")
        }
        
        batch.size
      } else {
        logger.error(s"Bulk request failed with status $statusCode")
        0
      }
    } match {
      case Success(count) => count
      case Failure(e) =>
        logger.error("Error indexing batch", e)
        0
    }
  }
  
  def close(): Unit = {
    Try {
      if (client != null) {
        client.close()
      }
    } match {
      case Success(_) => logger.info("OpenSearch client closed")
      case Failure(e) => logger.error("Error closing OpenSearch client", e)
    }
  }
}

object OpenSearchSink {
  def apply(
    endpoint: String,
    indexName: String,
    username: String = "admin",
    password: String = "Admin123!@#",
    batchSize: Int = 1000
  ): OpenSearchSink = {
    new OpenSearchSink(endpoint, indexName, username, password, batchSize)
  }
}
