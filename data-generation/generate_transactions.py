#!/usr/bin/env python3
"""
Gera dados de transações financeiras e envia para o S3

Este script gera dados realistas de transações com o seguinte esquema:
- codigo_lancamento: UUID (ID único da transação)
- numero_unico_conta: UUID (ID da conta dos dados de clientes)
- valor_total_transacao: Decimal (valor da transação)
- data_completa_transacao: data/hora ISO
- tipo_transacao: DEBITO ou CREDITO
- tipo_produto_transacao: PIX, TED ou CARTAO

Os dados são particionados por ano/mês/dia no S3
"""

import json
import uuid
import random
from datetime import datetime, timedelta
from typing import List, Dict
from decimal import Decimal
import boto3
from botocore.exceptions import ClientError


def load_config() -> Dict:
    """Carrega a configuração do config.json"""
    try:
        with open('config.json', 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        print("Error: config.json not found. Using default configuration.")
        return {
            "num_transactions": 1200,
            "start_date": "2024-01-01",
            "end_date": "2024-01-31",
            "aws_region": "us-east-1",
            "s3_bucket": "financial-transactions-dev-12345",
            "s3_prefix": "transactions"
        }


def load_customer_accounts() -> List[str]:
    """
    Carrega IDs de contas de clientes do arquivo salvo localmente.
    Se não disponível, gera IDs de conta de exemplo.
    """
    try:
        with open('output/customers.json', 'r') as f:
            customers = json.load(f)
            account_ids = [c['numero_unico_conta'] for c in customers]
            print(f"✓ Loaded {len(account_ids)} customer account IDs")
            return account_ids
    except FileNotFoundError:
        print("⚠ Warning: customers.json not found. Generating sample account IDs.")
        # Gera 25 IDs de conta de exemplo
        return [str(uuid.uuid4()) for _ in range(25)]


def generate_transaction(
    account_ids: List[str],
    transaction_date: datetime
) -> Dict:
    """
    Gera uma única transação.

    Args:
        account_ids: Lista de IDs de conta válidos
        transaction_date: Data/hora da transação

    Returns:
        Dicionário da transação
    """
    # Tipos de transação e produtos
    transaction_types = ['DEBITO', 'CREDITO']
    product_types = ['PIX', 'TED', 'CARTAO']

    # Gera valor da transação (R$ 10,00 a R$ 5000,00)
    amount = round(random.uniform(10.0, 5000.0), 2)

    transaction = {
        'codigo_lancamento': str(uuid.uuid4()),
        'numero_unico_conta': random.choice(account_ids),
        'valor_total_transacao': amount,
        'data_completa_transacao': transaction_date.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'tipo_transacao': random.choice(transaction_types),
        'tipo_produto_transacao': random.choice(product_types)
    }

    return transaction


def generate_transactions(
    num_transactions: int,
    account_ids: List[str],
    start_date: str,
    end_date: str
) -> Dict[str, List[Dict]]:
    """
    Gera transações distribuídas no intervalo de datas.

    Args:
        num_transactions: Número total de transações a gerar
        account_ids: Lista de IDs de conta válidos
        start_date: Data inicial (AAAA-MM-DD)
        end_date: Data final (AAAA-MM-DD)

    Returns:
        Dicionário mapeando chaves de partição às listas de transações
    """
    print(f"Generating {num_transactions} transactions...")

    start = datetime.strptime(start_date, '%Y-%m-%d')
    end = datetime.strptime(end_date, '%Y-%m-%d')
    date_range = (end - start).days + 1

    # Agrupa transações por partição (ano/mês/dia)
    partitioned_transactions = {}

    for i in range(num_transactions):
        # Data aleatória dentro do intervalo
        random_days = random.randint(0, date_range - 1)
        transaction_date = start + timedelta(days=random_days)

        # Horário aleatório durante o dia
        random_seconds = random.randint(0, 86399)  # 0 a 23:59:59
        transaction_datetime = transaction_date + \
            timedelta(seconds=random_seconds)

        # Gera a transação
        transaction = generate_transaction(account_ids, transaction_datetime)

        # Cria a chave de partição
        partition_key = (
            f"year={transaction_datetime.year}/"
            f"month={transaction_datetime.month:02d}/"
            f"day={transaction_datetime.day:02d}"
        )

        if partition_key not in partitioned_transactions:
            partitioned_transactions[partition_key] = []

        partitioned_transactions[partition_key].append(transaction)

        if (i + 1) % 100 == 0:
            print(f"  Generated {i + 1}/{num_transactions} transactions")

    print(
        f"✓ Generated {num_transactions} transactions across {len(partitioned_transactions)} partitions")

    return partitioned_transactions


def save_transactions_locally(partitioned_transactions: Dict[str, List[Dict]]):
    """Salva as transações em arquivos locais para referência"""
    import os

    os.makedirs('output/transactions', exist_ok=True)

    for partition_key, transactions in partitioned_transactions.items():
        # Cria nome de arquivo seguro a partir da chave de partição
        filename = partition_key.replace('/', '_') + '.json'
        filepath = f'output/transactions/{filename}'

        with open(filepath, 'w', encoding='utf-8') as f:
            json.dump(transactions, f, indent=2, ensure_ascii=False)

    print(f"✓ Saved transactions to output/transactions/")


def upload_to_s3(
    partitioned_transactions: Dict[str, List[Dict]],
    bucket_name: str,
    prefix: str,
    region: str
):
    """
    Envia transações para o S3 com particionamento.

    Args:
        partitioned_transactions: Dicionário partição -> transações
        bucket_name: Nome do bucket S3
        prefix: Prefixo da chave S3
        region: Região AWS
    """
    print(f"\nUploading to S3 bucket: {bucket_name}")

    s3_client = boto3.client('s3', region_name=region)

    total_uploaded = 0

    try:
        for partition_key, transactions in partitioned_transactions.items():
            # Cria chave S3 com a partição
            s3_key = f"{prefix}/{partition_key}/transactions_{uuid.uuid4().hex[:8]}.json"

            # Converte para JSON
            json_data = json.dumps(transactions, indent=2, ensure_ascii=False)

            # Envia para o S3
            s3_client.put_object(
                Bucket=bucket_name,
                Key=s3_key,
                Body=json_data.encode('utf-8'),
                ContentType='application/json'
            )

            total_uploaded += len(transactions)
            print(f"  Uploaded {len(transactions)} transactions to {s3_key}")

        print(f"✓ Successfully uploaded {total_uploaded} transactions to S3")

    except ClientError as e:
        print(f"✗ Error uploading to S3: {e.response['Error']['Message']}")
        raise
    except Exception as e:
        print(f"✗ Unexpected error: {str(e)}")
        raise


def verify_upload(bucket_name: str, prefix: str, region: str):
    """Verifica se os dados foram enviados corretamente"""
    print(f"\nVerifying upload...")

    s3_client = boto3.client('s3', region_name=region)

    try:
        response = s3_client.list_objects_v2(
            Bucket=bucket_name,
            Prefix=f"{prefix}/"
        )

        if 'Contents' in response:
            file_count = len(response['Contents'])
            total_size = sum(obj['Size'] for obj in response['Contents'])

            print(f"  Files uploaded: {file_count}")
            print(f"  Total size: {total_size / 1024:.2f} KB")
            print(f"✓ Verification successful!")
        else:
            print(f"⚠ Warning: No files found in S3")

    except ClientError as e:
        print(f"✗ Error verifying upload: {e.response['Error']['Message']}")


def display_statistics(partitioned_transactions: Dict[str, List[Dict]]):
    """Exibe estatísticas sobre as transações geradas"""
    print("\n" + "=" * 60)
    print("Transaction Statistics")
    print("=" * 60)

    total_transactions = sum(len(txns)
                             for txns in partitioned_transactions.values())

    # Contagem por tipo
    type_counts = {'DEBITO': 0, 'CREDITO': 0}
    product_counts = {'PIX': 0, 'TED': 0, 'CARTAO': 0}
    total_value = 0.0

    for transactions in partitioned_transactions.values():
        for txn in transactions:
            type_counts[txn['tipo_transacao']] += 1
            product_counts[txn['tipo_produto_transacao']] += 1
            total_value += txn['valor_total_transacao']

    print(f"\nTotal Transactions: {total_transactions}")
    print(f"Total Value: R$ {total_value:,.2f}")
    print(f"Average Value: R$ {total_value / total_transactions:,.2f}")

    print(f"\nBy Transaction Type:")
    for txn_type, count in type_counts.items():
        percentage = (count / total_transactions) * 100
        print(f"  {txn_type}: {count} ({percentage:.1f}%)")

    print(f"\nBy Product Type:")
    for product, count in product_counts.items():
        percentage = (count / total_transactions) * 100
        print(f"  {product}: {count} ({percentage:.1f}%)")

    print(f"\nPartitions: {len(partitioned_transactions)}")
    for partition_key in sorted(partitioned_transactions.keys()):
        count = len(partitioned_transactions[partition_key])
        print(f"  {partition_key}: {count} transactions")


def main():
    """Função principal de execução"""
    print("=" * 60)
    print("Transaction Data Generator for S3")
    print("=" * 60)

    # Carrega a configuração
    config = load_config()
    num_transactions = config.get('num_transactions', 1200)
    start_date = config.get('start_date', '2024-01-01')
    end_date = config.get('end_date', '2024-01-31')
    bucket_name = config.get('s3_bucket', 'financial-transactions-dev-12345')
    prefix = config.get('s3_prefix', 'transactions')
    region = config.get('aws_region', 'us-east-1')

    print(f"\nConfiguration:")
    print(f"  Number of transactions: {num_transactions}")
    print(f"  Date range: {start_date} to {end_date}")
    print(f"  S3 bucket: {bucket_name}")
    print(f"  S3 prefix: {prefix}")
    print(f"  AWS region: {region}")
    print()

    # Carrega IDs de contas de clientes
    account_ids = load_customer_accounts()

    # Gera transações
    partitioned_transactions = generate_transactions(
        num_transactions,
        account_ids,
        start_date,
        end_date
    )

    # Salva localmente para referência
    save_transactions_locally(partitioned_transactions)

    # Envia para o S3
    upload_to_s3(partitioned_transactions, bucket_name, prefix, region)

    # Verifica o envio
    verify_upload(bucket_name, prefix, region)

    # Exibe estatísticas
    display_statistics(partitioned_transactions)

    print("\n" + "=" * 60)
    print("Transaction data generation completed!")
    print("=" * 60)

    # Exibe transação de exemplo
    sample_partition = list(partitioned_transactions.keys())[0]
    sample_transaction = partitioned_transactions[sample_partition][0]
    print(f"\nSample transaction from {sample_partition}:")
    print(json.dumps(sample_transaction, indent=2, ensure_ascii=False))


if __name__ == '__main__':
    main()
