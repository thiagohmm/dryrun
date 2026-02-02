package models

import java.sql.Timestamp

/**
 * Case class representing a financial transaction from S3
 * Schema matches the JSON structure in S3 (snake_case)
 */
case class Transaction(
  codigo_lancamento: String,
  numero_unico_conta: String,
  valor_total_transacao: Double,
  data_completa_transacao: Timestamp,
  tipo_transacao: String,
  tipo_produto_transacao: String
)

/**
 * Case class representing customer data from DynamoDB
 */
case class CustomerData(
  numero_unico_conta: String,
  nome_titular_conta: String,
  data_nascimento_titular_conta: Timestamp,
  zipCode: String,
  data_criacao_registro: String
)

/**
 * Case class representing enriched transaction for OpenSearch
 * All fields in camelCase as per requirements
 */
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

object EnrichedTransaction {
  /**
   * Create an enriched transaction by merging transaction and customer data
   */
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
