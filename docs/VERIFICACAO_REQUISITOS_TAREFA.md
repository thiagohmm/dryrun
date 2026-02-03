# Verificação da tarefa – Dry-Run Ingestão Glue Batch

Este documento confere o projeto em relação ao enunciado da tarefa (requisitos funcionais, não funcionais, schemas e entrega).

---

## 1. Descrição da arquitetura

| Exigência                                                                        | Status | Verificação no projeto                                                                                                         |
| -------------------------------------------------------------------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------ |
| Dados em JSON no S3, particionados por ano/mês/dia (lançamentos financeiros)     | ✅ OK  | Caminho `s3://bucket/transactions/year=.../month=.../day=.../`; scripts Python geram JSON com essa partição.                   |
| Consumo via AWS Glue Job em **Scala**                                            | ✅ OK  | `FinancialTransactionProcessor.scala`; job configurado com `--job-language scala`, `--class FinancialTransactionProcessor`.    |
| Uso de **MapPartitions** para consulta em **BATCH** ao DynamoDB (enriquecimento) | ✅ OK  | `transactions.rdd.mapPartitions { ... }`; dentro do closure, `enricher.batchGetCustomerData(uniqueAccountIds)` (BatchGetItem). |
| Persistência dos lançamentos no **OpenSearch**                                   | ✅ OK  | `OpenSearchSink.writeBulk`; índice configurado no Terraform e criado/verificado no código.                                     |

---

## 2. Schema dos dados no S3

| Campo (enunciado)       | Tipo             | Status | No projeto                                                                             |
| ----------------------- | ---------------- | ------ | -------------------------------------------------------------------------------------- |
| codigo_lancamento       | guid             | ✅ OK  | `Transaction.codigo_lancamento: String` (UUID)                                         |
| numero_unico_conta      | guid             | ✅ OK  | `Transaction.numero_unico_conta: String` (UUID)                                        |
| valor_total_transacao   | decimal          | ✅ OK  | `Transaction.valor_total_transacao: Double`                                            |
| data_completa_transacao | date_time        | ✅ OK  | `Transaction.data_completa_transacao: Timestamp`; formato ISO no JSON.                 |
| tipo_transacao          | DEBITO, CREDITO  | ✅ OK  | `Transaction.tipo_transacao: String`; geradores usam `['DEBITO','CREDITO']`.           |
| tipo_produto_transacao  | PIX, TED, CARTAO | ✅ OK  | `Transaction.tipo_produto_transacao: String`; geradores usam `['PIX','TED','CARTAO']`. |

---

## 3. Schema da tabela DynamoDB

| Campo (enunciado)             | Tipo      | Status | No projeto                                                          |
| ----------------------------- | --------- | ------ | ------------------------------------------------------------------- |
| numero_unico_conta            | guid      | ✅ OK  | PK; `CustomerData.numero_unico_conta`                               |
| nome_titular_conta            | string    | ✅ OK  | `CustomerData.nome_titular_conta`                                   |
| data_nascimento_titular_conta | date_time | ✅ OK  | `CustomerData.data_nascimento_titular_conta: Timestamp`             |
| zip-code                      | string    | ✅ OK  | `CustomerData.zipCode` (mapeado do atributo `zip-code` no DynamoDB) |
| data_criacao_registro         | date      | ✅ OK  | `CustomerData.data_criacao_registro: String` (ex.: `YYYY-MM-DD`)    |

---

## 4. Infraestrutura e entrega (enunciado)

| Exigência                               | Status | Verificação                                                                                |
| --------------------------------------- | ------ | ------------------------------------------------------------------------------------------ |
| Infra criada + parte funcional dos jobs | ✅ OK  | Terraform (S3, DynamoDB, OpenSearch, Glue, IAM, etc.) + job Scala completo.                |
| Infra provisionada via **IaC**          | ✅ OK  | Terraform em `infrastructure/` (main, variables, outputs, s3, dynamodb, opensearch, glue). |
| Código IaC e Glue Job no entregável     | ✅ OK  | Tudo versionado; entrega em ZIP conforme doc de demo.                                      |

---

## 5. Requisitos não funcionais

| #   | Requisito                                                                                       | Status     | Verificação                                                                                                                                                                                                                                                                                                                                                                         |
| --- | ----------------------------------------------------------------------------------------------- | ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Dados no S3 em formato **JSON**                                                                 | ✅ OK      | Leitura `spark.read.json(s3Path)`; geradores gravam `.json`.                                                                                                                                                                                                                                                                                                                        |
| 2   | Lançamentos no OpenSearch em **JSON camelCase**                                                 | ✅ OK      | `EnrichedTransaction` em camelCase; serialização Jackson para o índice.                                                                                                                                                                                                                                                                                                             |
| 3   | Glue Job em **Scala**                                                                           | ✅ OK      | Código em Scala 2.12; `build.sbt`, classe principal em Scala.                                                                                                                                                                                                                                                                                                                       |
| 4   | **Enriquecimento e armazenamento** no OpenSearch realizados através da **função MapPartitions** | ⚠️ Atenção | **Enriquecimento**: feito com `mapPartitions`. **Armazenamento**: feito com `foreachPartition` (gravação no OpenSearch). O enunciado diz “através da função MapPartitions”; tecnicamente a escrita não usa `mapPartitions`. Ver observação abaixo.                                                                                                                                  |
| 5   | OpenSearch: instância pequena ou serverless; domínio privado (VPC) ou público (IP)              | ✅ OK      | Terraform permite `t3.small.search`, contagem de nós configurável; `opensearch_allowed_ips` para acesso público.                                                                                                                                                                                                                                                                    |
| 6   | Leitura cadastral com **BATCH-GET** do DynamoDB                                                 | ✅ OK      | `DynamoDBEnricher.batchGetCustomerData` usa `BatchGetItemRequest` / `batchGetItem`; lotes de 100.                                                                                                                                                                                                                                                                                   |
| 7   | Tabela DynamoDB provisionada ou on-demand                                                       | ✅ OK      | `dynamodb_billing_mode` (PROVISIONED ou PAY_PER_REQUEST); exemplo em `terraform.tfvars.example`.                                                                                                                                                                                                                                                                                    |
| 8   | Infra do Glue job com IaC; “código ser feito diretamente pelo console da AWS”                   | ⚠️ Atenção | **IaC do job**: ✅ Terraform cria o job Glue (nome, role, script location, etc.). **Código no console**: o projeto desenvolve o Scala em repositório e envia o JAR ao S3; o job roda esse JAR no Glue. Se a banca exigir literalmente “código escrito no editor do console Glue”, isso não é atendido. Se aceitarem “código executado no Glue (console)” como atendimento, está OK. |
| 9   | Tudo em uma região e uma conta                                                                  | ✅ OK      | Variável `aws_region`; sem multi-region/multi-account.                                                                                                                                                                                                                                                                                                                              |
| 10  | Glue job **versão 4.0 ou 5.0**                                                                  | ✅ OK      | `glue_version` em variables.tf (default `"4.0"`); exemplo com `"4.0"` ou `"5.0"`.                                                                                                                                                                                                                                                                                                   |

---

## 6. Requisitos funcionais

| #   | Requisito                                                                                                            | Status | Verificação                                                                                                                                   |
| --- | -------------------------------------------------------------------------------------------------------------------- | ------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Glue lê S3 para **ano/mês/dia**, enriquece com DynamoDB e ingere no OpenSearch                                       | ✅ OK  | Argumentos `--year`, `--month`, `--day`; caminho `year=$year/month=$month/day=$day/`; enriquecimento + `OpenSearchSink.writeBulk`.            |
| 2   | Enriquecimento usa o campo **numero_unico_conta** na consulta à tabela cadastral                                     | ✅ OK  | `uniqueAccountIds = chunk.map(_.numero_unico_conta).toSet`; `batchGetCustomerData(uniqueAccountIds)`; chave da tabela é `numero_unico_conta`. |
| 3   | Múltiplos lançamentos para uma mesma conta                                                                           | ✅ OK  | Várias transações podem ter o mesmo `numero_unico_conta`; batch-get traz o cliente uma vez e reutiliza no chunk.                              |
| 4   | Dados de S3 e DynamoDB **gerados pelo candidato**; testes com **≥ 1000 registros no S3** e **≥ 20 contas distintas** | ✅ OK  | `generate_customers.py` e `generate_transactions.py`; `config.json`: `num_customers: 25`, `num_transactions: 1200` (atende 1000+ e 20+).      |

---

## 7. Desafio extra

| Exigência                                                | Status | Verificação                                                                           |
| -------------------------------------------------------- | ------ | ------------------------------------------------------------------------------------- |
| Passos 1 e 3 obrigatórios: ler S3 e salvar no OpenSearch | ✅ OK  | Leitura S3 por ano/mês/dia; escrita no OpenSearch via `OpenSearchSink`.               |
| Passo 2: enriquecimento com cadastro (se possível)       | ✅ OK  | Implementado com MapPartitions + DynamoDB batch-get e merge em `EnrichedTransaction`. |

---

## 8. Entrega final e demo

| Exigência                                                  | Status | Verificação                                                                 |
| ---------------------------------------------------------- | ------ | --------------------------------------------------------------------------- |
| Apresentação do progresso                                  | ✅ OK  | Guia em `docs/DEMO.md`.                                                     |
| Um único ZIP com todo o código                             | ✅ OK  | Instruções no `DEMO.md` (comando `zip` e exclusões).                        |
| Prazo de uma semana                                        | —      | A cargo do candidato.                                                       |
| **Tracking de tempo (horas)** investido e informar na demo | ✅ OK  | `TIME_TRACKING.md` no repositório para preenchimento e apresentação no dia. |

---

## 9. Resumo

- **Atendidos sem ressalva:** descrição da arquitetura, schemas S3 e DynamoDB, infra via IaC, requisitos não funcionais 1, 2, 3, 5, 6, 7, 9, 10, todos os requisitos funcionais, desafio extra e formato de entrega/demo/tempo.
- **Pontos de atenção:**
  1. **Requisito não funcional 4 (MapPartitions para enriquecimento e armazenamento):** hoje o armazenamento no OpenSearch é feito em `foreachPartition`. Se a banca interpretar que “armazenamento” também deve estar **dentro** de `mapPartitions`, seria necessário unificar: um único `mapPartitions` que enriquece e grava no OpenSearch (sem `foreachPartition`).
  2. **Requisito não funcional 8 (“código ser feito diretamente pelo console da AWS”):** o projeto usa código Scala em repositório e JAR no S3. Se a interpretação for “código escrito no editor do Glue Studio”, não está atendido; se for “job executado no Glue”, está.

---

## 10. Conclusão

A solução atende à grande maioria dos requisitos da tarefa. Os únicos pontos que podem exigir alinhamento com a banca são:

- Uso de **foreachPartition** para escrita no OpenSearch (em vez de fazer essa escrita dentro do mesmo **mapPartitions**).
- Onde o “código” do Glue deve ser desenvolvido (repositório + JAR vs. editor do console).

Recomendação: na demo, deixar claro que o enriquecimento é feito com MapPartitions e a escrita é feita por partição (foreachPartition), e que o código do job está versionado e é implantado via JAR no S3 para reprodutibilidade e boas práticas de desenvolvimento.
