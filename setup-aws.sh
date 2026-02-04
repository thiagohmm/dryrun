#!/bin/bash

# Script de configuração rápida AWS
# Execute este script após gerar as Access Keys no console AWS

echo "🔑 Configuração AWS para Terraform Dry-Run"
echo "=========================================="
echo ""
echo "Account ID: 160885283918"
echo "Region: us-east-2 (Ohio)"
echo ""
echo "Iniciando configuração AWS CLI..."
echo ""

# Configurar AWS CLI
aws configure

echo ""
echo "✅ Configuração concluída!"
echo ""
echo "🧪 Testando credenciais..."
aws sts get-caller-identity

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Credenciais válidas!"
    echo ""
    echo "🏗️ Executando Terraform Plan (Dry-Run)..."
    cd /home/thiagohmm/Estudo/dryRun/infrastructure
    terraform plan
    
    echo ""
    echo "=========================================="
    echo "✅ Dry-Run concluído!"
    echo ""
    echo "Para aplicar a infraestrutura, execute:"
    echo "  cd /home/thiagohmm/Estudo/dryRun/infrastructure"
    echo "  terraform apply"
    echo ""
    echo "Para destruir os recursos depois:"
    echo "  terraform destroy"
else
    echo ""
    echo "❌ Erro ao validar credenciais. Verifique as Access Keys."
fi
