.PHONY: help init plan apply destroy generate-data build-glue deploy-glue run-glue clean

help:
	@echo "Available commands:"
	@echo "  make init          - Initialize Terraform"
	@echo "  make plan          - Plan Terraform changes"
	@echo "  make apply         - Apply Terraform infrastructure"
	@echo "  make destroy       - Destroy Terraform infrastructure"
	@echo "  make generate-data - Generate test data"
	@echo "  make build-glue    - Build Glue Job JAR"
	@echo "  make deploy-glue   - Deploy Glue Job to S3"
	@echo "  make run-glue      - Run Glue Job"
	@echo "  make clean         - Clean build artifacts"

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
	cd glue-job && sbt clean package

deploy-glue: build-glue
	@echo "Deploying Glue Job JAR to S3..."
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
