#!/bin/bash

# Script para verificar status e resultados do job Glue

set -e

JOB_NAME="financial-transaction-processor-dev"
REGION="us-east-2"
OPENSEARCH_ENDPOINT="search-financial-txns-dev-lav5rhlpqqpdipxeqhwmb2rp6e.us-east-2.es.amazonaws.com"
OPENSEARCH_INDEX="financial-transactions"
OPENSEARCH_USER="admin"
OPENSEARCH_PASS="Admin123!@#"

echo "============================================================"
echo "🔍 Verificação do Job Glue: $JOB_NAME"
echo "============================================================"
echo ""

# 1. Última execução
echo "1️⃣  Status da Última Execução:"
echo "-----------------------------------------------------------"
LAST_RUN=$(aws glue get-job-runs \
  --job-name "$JOB_NAME" \
  --max-results 1 \
  --region "$REGION" \
  --query 'JobRuns[0]' 2>/dev/null)

if [ -z "$LAST_RUN" ] || [ "$LAST_RUN" = "null" ]; then
  echo "❌ Nenhuma execução encontrada"
  exit 1
fi

JOB_RUN_ID=$(echo "$LAST_RUN" | jq -r '.Id')
JOB_STATE=$(echo "$LAST_RUN" | jq -r '.JobRunState')
STARTED_ON=$(echo "$LAST_RUN" | jq -r '.StartedOn')
COMPLETED_ON=$(echo "$LAST_RUN" | jq -r '.CompletedOn // "Em execução..."')
EXECUTION_TIME=$(echo "$LAST_RUN" | jq -r '.ExecutionTime // 0')
ERROR_MSG=$(echo "$LAST_RUN" | jq -r '.ErrorMessage // "Nenhum erro"')

echo "  Job Run ID: $JOB_RUN_ID"
echo "  Status: $JOB_STATE"
echo "  Iniciado em: $(date -d @${STARTED_ON%.*} 2>/dev/null || echo $STARTED_ON)"
echo "  Completado em: $(date -d @${COMPLETED_ON%.*} 2>/dev/null || echo $COMPLETED_ON)"
echo "  Tempo de execução: ${EXECUTION_TIME}s"

if [ "$JOB_STATE" = "SUCCEEDED" ]; then
  echo "  ✅ Job executado com SUCESSO!"
elif [ "$JOB_STATE" = "RUNNING" ]; then
  echo "  ⏳ Job ainda está EXECUTANDO..."
elif [ "$JOB_STATE" = "FAILED" ]; then
  echo "  ❌ Job FALHOU!"
  echo "  Erro: $ERROR_MSG"
else
  echo "  ⚠️  Status: $JOB_STATE"
fi

echo ""

# 2. CloudWatch Logs (últimas linhas)
echo "2️⃣  Últimas Linhas dos Logs (CloudWatch):"
echo "-----------------------------------------------------------"
LOG_GROUP="/aws-glue/jobs/output"
LOG_STREAM_PREFIX="$JOB_RUN_ID"

# Tenta pegar os logs mais recentes
LOG_STREAMS=$(aws logs describe-log-streams \
  --log-group-name "$LOG_GROUP" \
  --log-stream-name-prefix "$LOG_STREAM_PREFIX" \
  --max-items 1 \
  --region "$REGION" \
  --query 'logStreams[0].logStreamName' \
  --output text 2>/dev/null || echo "")

if [ -n "$LOG_STREAMS" ] && [ "$LOG_STREAMS" != "None" ]; then
  echo "  📋 Log Stream: $LOG_STREAMS"
  echo ""
  aws logs get-log-events \
    --log-group-name "$LOG_GROUP" \
    --log-stream-name "$LOG_STREAMS" \
    --limit 20 \
    --region "$REGION" \
    --query 'events[*].message' \
    --output text 2>/dev/null | tail -10 | sed 's/^/    /'
else
  echo "  ⚠️  Logs ainda não disponíveis (job pode estar iniciando)"
fi

echo ""

# 3. Verificar dados no OpenSearch
if [ "$JOB_STATE" = "SUCCEEDED" ]; then
  echo "3️⃣  Verificação no OpenSearch:"
  echo "-----------------------------------------------------------"
  
  # Conta documentos no índice
  DOC_COUNT=$(curl -s -u "$OPENSEARCH_USER:$OPENSEARCH_PASS" \
    "https://$OPENSEARCH_ENDPOINT/$OPENSEARCH_INDEX/_count" 2>/dev/null | jq -r '.count // 0')
  
  echo "  📊 Total de documentos indexados: $DOC_COUNT"
  
  if [ "$DOC_COUNT" -gt 0 ]; then
    echo "  ✅ Dados encontrados no OpenSearch!"
    echo ""
    echo "  📄 Exemplo de documento:"
    curl -s -u "$OPENSEARCH_USER:$OPENSEARCH_PASS" \
      "https://$OPENSEARCH_ENDPOINT/$OPENSEARCH_INDEX/_search?size=1&pretty" 2>/dev/null | \
      jq '.hits.hits[0]._source' | sed 's/^/    /'
  else
    echo "  ⚠️  Nenhum documento encontrado no OpenSearch"
  fi
  
  echo ""
  
  # 4. Estatísticas
  echo "4️⃣  Estatísticas dos Dados:"
  echo "-----------------------------------------------------------"
  
  STATS=$(curl -s -u "$OPENSEARCH_USER:$OPENSEARCH_PASS" \
    "https://$OPENSEARCH_ENDPOINT/$OPENSEARCH_INDEX/_search?size=0&pretty" \
    -H 'Content-Type: application/json' \
    -d '{
      "aggs": {
        "tipo_transacao": { "terms": { "field": "tipoTransacao" } },
        "tipo_produto": { "terms": { "field": "tipoProdutoTransacao" } },
        "valor_total": { "sum": { "field": "valorTotalTransacao" } },
        "valor_medio": { "avg": { "field": "valorTotalTransacao" } }
      }
    }' 2>/dev/null)
  
  echo "  Valor Total: R$ $(echo "$STATS" | jq -r '.aggregations.valor_total.value // 0' | numfmt --grouping 2>/dev/null || echo "$STATS" | jq -r '.aggregations.valor_total.value // 0')"
  echo "  Valor Médio: R$ $(echo "$STATS" | jq -r '.aggregations.valor_medio.value // 0' | xargs printf "%.2f")"
  echo ""
  echo "  Por Tipo de Transação:"
  echo "$STATS" | jq -r '.aggregations.tipo_transacao.buckets[] | "    \(.key): \(.doc_count) transações"'
  echo ""
  echo "  Por Tipo de Produto:"
  echo "$STATS" | jq -r '.aggregations.tipo_produto.buckets[] | "    \(.key): \(.doc_count) transações"'
fi

echo ""
echo "============================================================"
echo "🔗 Links Úteis:"
echo "============================================================"
echo "  CloudWatch Logs: https://us-east-2.console.aws.amazon.com/cloudwatch/home?region=us-east-2#logsV2:log-groups/log-group/\$252Faws-glue\$252Fjobs\$252Foutput"
echo "  OpenSearch Dashboards: https://$OPENSEARCH_ENDPOINT/_dashboards/"
echo "  Glue Console: https://us-east-2.console.aws.amazon.com/gluestudio/home?region=us-east-2#/jobs"
echo ""
