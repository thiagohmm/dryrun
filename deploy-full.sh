#!/bin/bash

# Script de deployment completo para o Financial Transaction Processor
# Este script:
# 1. Aplica a infraestrutura Terraform
# 2. Compila o job Scala
# 3. Faz upload do JAR para S3
# 4. Atualiza o job Glue com o JAR correto

set -e  # Exit on error

echo "🚀 Financial Transaction Processor - Deployment Completo"
echo "=========================================================="
echo ""

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Função para print colorido
print_step() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Diretório raiz do projeto
PROJECT_ROOT="/home/thiagohmm/Estudo/dryRun"
cd "$PROJECT_ROOT"

# Verificar se AWS CLI está configurado
echo "🔍 Verificando configuração AWS..."
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    print_error "AWS CLI não está configurado. Execute 'aws configure' primeiro."
    exit 1
fi
print_step "AWS CLI configurado corretamente"
echo ""

# Passo 1: Upload do placeholder para S3 (necessário para terraform apply)
echo "📤 Passo 1: Preparando ambiente..."
cd infrastructure

# Obter o nome do bucket (se já existir)
if terraform output glue_scripts_bucket > /dev/null 2>&1; then
    BUCKET=$(terraform output -raw glue_scripts_bucket)
    print_step "Bucket já existe: $BUCKET"
    
    # Upload placeholder
    aws s3 cp ../glue-job/placeholder.scala s3://$BUCKET/scripts/placeholder.scala
    print_step "Placeholder uploaded"
fi
echo ""

# Passo 2: Aplicar Terraform
echo "🏗️  Passo 2: Aplicando infraestrutura Terraform..."
terraform init -upgrade
print_step "Terraform inicializado"

terraform apply -auto-approve
print_step "Infraestrutura criada com sucesso"
echo ""

# Passo 3: Obter outputs do Terraform
echo "📋 Passo 3: Obtendo informações da infraestrutura..."
BUCKET=$(terraform output -raw glue_scripts_bucket)
JOB_NAME=$(terraform output -raw glue_job_name)
OPENSEARCH_ENDPOINT=$(terraform output -raw opensearch_endpoint)
S3_TRANSACTIONS=$(terraform output -raw s3_transactions_bucket)
DYNAMODB_TABLE=$(terraform output -raw dynamodb_table_name)
AWS_REGION=$(terraform output -raw aws_region)

print_step "Bucket Glue Scripts: $BUCKET"
print_step "Job Name: $JOB_NAME"
print_step "OpenSearch: $OPENSEARCH_ENDPOINT"
echo ""

# Passo 4: Verificar SBT
echo "🔍 Passo 4: Verificando SBT..."
if ! command -v sbt &> /dev/null; then
    print_error "SBT não está instalado. Instalando..."
    echo "deb https://repo.scala-sbt.org/scalasbt/debian all main" | sudo tee /etc/apt/sources.list.d/sbt.list
    curl -sL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x2EE0EA64E40A89B84B2DF73499E82A75642AC823" | sudo apt-key add
    sudo apt-get update
    sudo apt-get install -y sbt
fi
print_step "SBT disponível: $(sbt --version | head -1)"
echo ""

# Passo 5: Compilar Scala
echo "⚙️  Passo 5: Compilando job Scala..."
cd "$PROJECT_ROOT/glue-job"
sbt clean assembly
print_step "JAR compilado com sucesso"
echo ""

# Passo 6: Upload do JAR para S3
echo "📤 Passo 6: Fazendo upload do JAR para S3..."
JAR_FILE=$(find target/scala-2.12 -name "*assembly*.jar" | head -1)

if [ -z "$JAR_FILE" ]; then
    print_error "JAR não encontrado em target/scala-2.12"
    exit 1
fi

JAR_NAME=$(basename "$JAR_FILE")
aws s3 cp "$JAR_FILE" "s3://$BUCKET/scripts/$JAR_NAME"
print_step "JAR uploaded: s3://$BUCKET/scripts/$JAR_NAME"
echo ""

# Passo 7: Atualizar job Glue
echo "🔧 Passo 7: Atualizando job Glue com o JAR correto..."
aws glue update-job \
    --job-name "$JOB_NAME" \
    --job-update "{
        \"Command\": {
            \"Name\": \"glueetl\",
            \"ScriptLocation\": \"s3://$BUCKET/scripts/$JAR_NAME\",
            \"PythonVersion\": \"3\"
        }
    }" > /dev/null

print_step "Job Glue atualizado com sucesso"
echo ""

# Passo 8: Criar arquivo de configuração para execução
echo "📝 Passo 8: Criando arquivo de configuração..."
cat > "$PROJECT_ROOT/job-config.env" << EOF
# Configuração do Job Glue
export JOB_NAME="$JOB_NAME"
export S3_BUCKET="$S3_TRANSACTIONS"
export DYNAMODB_TABLE="$DYNAMODB_TABLE"
export OPENSEARCH_ENDPOINT="$OPENSEARCH_ENDPOINT"
export OPENSEARCH_INDEX="financial-transactions"
export AWS_REGION="$AWS_REGION"

# Para executar o job:
# aws glue start-job-run --job-name \$JOB_NAME --arguments '{
#   "--year":"2024",
#   "--month":"01",
#   "--day":"15",
#   "--s3_bucket":"'\$S3_BUCKET'",
#   "--dynamodb_table":"'\$DYNAMODB_TABLE'",
#   "--opensearch_endpoint":"'\$OPENSEARCH_ENDPOINT'",
#   "--opensearch_index":"'\$OPENSEARCH_INDEX'",
#   "--aws_region":"'\$AWS_REGION'"
# }'
EOF

print_step "Arquivo de configuração criado: job-config.env"
echo ""

# Resumo
echo "=========================================================="
echo -e "${GREEN}✅ DEPLOYMENT CONCLUÍDO COM SUCESSO!${NC}"
echo "=========================================================="
echo ""
echo "📊 Recursos Criados:"
echo "  • Bucket S3 Transações: $S3_TRANSACTIONS"
echo "  • Bucket S3 Scripts: $BUCKET"
echo "  • Tabela DynamoDB: $DYNAMODB_TABLE"
echo "  • Domínio OpenSearch: $OPENSEARCH_ENDPOINT"
echo "  • Job Glue: $JOB_NAME"
echo ""
echo "🚀 Próximos Passos:"
echo ""
echo "1. Gerar dados de teste:"
echo "   cd $PROJECT_ROOT"
echo "   make generate-data"
echo ""
echo "2. Executar o job Glue:"
echo "   make run-glue"
echo "   # Ou manualmente:"
echo "   aws glue start-job-run --job-name $JOB_NAME \\"
echo "     --arguments '{\"--year\":\"2024\",\"--month\":\"01\",\"--day\":\"15\"}'"
echo ""
echo "3. Monitorar execução:"
echo "   aws glue get-job-runs --job-name $JOB_NAME"
echo ""
echo "4. Ver logs:"
echo "   aws logs tail /aws-glue/jobs/$JOB_NAME --follow"
echo ""
echo "5. Acessar OpenSearch Dashboard:"
echo "   https://$OPENSEARCH_ENDPOINT/_dashboards"
echo ""
echo "=========================================================="
