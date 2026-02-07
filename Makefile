.PHONY: help setup-aws aws-test init plan apply destroy generate-data build-glue deploy-glue run-glue clean

help:
	@echo "🚀 Comandos disponíveis:"
	@echo ""
	@echo "AWS Setup:"
	@echo "  make setup-aws     - Configura credenciais AWS (interativo)"
	@echo "  make aws-test      - Testa credenciais AWS"
	@echo ""
	@echo "Terraform:"
	@echo "  make init          - Inicializa o Terraform"
	@echo "  make plan          - Planeja alterações (DRY-RUN)"
	@echo "  make apply         - Aplica a infraestrutura"
	@echo "  make destroy       - Destrói a infraestrutura"
	@echo ""
	@echo "Dados e Glue:"
	@echo "  make generate-data - Gera dados de teste"
	@echo "  make build-glue    - Compila o JAR do job Glue"
	@echo "  make deploy-glue   - Implanta o job Glue no S3"
	@echo "  make run-glue      - Executa o job Glue"
	@echo "  make clean         - Remove artefatos de build"

setup-aws:
	@echo "🔑 Configurando credenciais AWS..."
	@echo "Account: 160885283918"
	@echo "Region: us-east-2 (Ohio)"
	@echo ""
	@bash setup-aws.sh

aws-test:
	@echo "🧪 Testando credenciais AWS..."
	@aws sts get-caller-identity
	@echo ""
	@echo "Region configurada:"
	@aws configure get region

init:
	cd infrastructure && terraform init

plan:
	cd infrastructure && terraform plan

apply:
	cd infrastructure && terraform apply

destroy:
	cd infrastructure && terraform destroy

generate-data:
	cd data-generation && pip install -r requirements.txt
	cd data-generation && python generate_customers.py
	cd data-generation && python generate_transactions.py

build-glue:
	cd glue-job && sbt clean assembly

deploy-glue: build-glue
	@echo "Implantando JAR do job Glue no S3..."
	@BUCKET=$$(cd infrastructure && terraform output -raw glue_scripts_bucket); \
	aws s3 cp glue-job/target/scala-2.12/financial-transaction-processor_2.12-1.0.jar s3://$$BUCKET/scripts/

run-glue:
	@JOB_NAME=$$(cd infrastructure && terraform output -raw glue_job_name); \
	aws glue start-job-run --job-name $$JOB_NAME \
		--arguments='--year=2024,--month=01,--day=15'

clean:
	cd glue-job && sbt clean
	rm -rf data-generation/__pycache__
	rm -rf data-generation/output
