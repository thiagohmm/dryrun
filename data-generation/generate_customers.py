#!/usr/bin/env python3
"""
Generate customer registration data and upload to DynamoDB

This script generates realistic customer data with the following schema:
- numero_unico_conta: UUID (Primary Key)
- nome_titular_conta: Full name
- data_nascimento_titular_conta: Birth date (ISO format)
- zip-code: Brazilian ZIP code format (12345-678)
- data_criacao_registro: Account creation date
"""

import json
import uuid
from datetime import datetime, timedelta
from typing import List, Dict
import boto3
from faker import Faker
from botocore.exceptions import ClientError

# Initialize Faker with Brazilian locale
fake = Faker('pt_BR')


def load_config() -> Dict:
    """Load configuration from config.json"""
    try:
        with open('config.json', 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        print("Error: config.json not found. Using default configuration.")
        return {
            "num_customers": 25,
            "aws_region": "us-east-1",
            "dynamodb_table": "customer-registration-dev"
        }


def generate_customer_data(num_customers: int) -> List[Dict]:
    """
    Generate customer registration data

    Args:
        num_customers: Number of customer records to generate

    Returns:
        List of customer dictionaries
    """
    customers = []

    print(f"Generating {num_customers} customer records...")

    for i in range(num_customers):
        # Generate birth date (18-80 years old)
        birth_date = fake.date_of_birth(minimum_age=18, maximum_age=80)

        # Generate account creation date (within last 5 years)
        days_ago = fake.random_int(min=1, max=1825)  # 5 years
        creation_date = datetime.now() - timedelta(days=days_ago)

        customer = {
            'numero_unico_conta': str(uuid.uuid4()),
            'nome_titular_conta': fake.name(),
            'data_nascimento_titular_conta': birth_date.strftime('%Y-%m-%dT%H:%M:%SZ'),
            'zip-code': fake.postcode(),  # Brazilian format: 12345-678
            'data_criacao_registro': creation_date.strftime('%Y-%m-%d')
        }

        customers.append(customer)

        if (i + 1) % 10 == 0:
            print(f"  Generated {i + 1}/{num_customers} customers")

    print(f"✓ Generated {len(customers)} customer records")
    return customers


def save_customers_locally(customers: List[Dict], filename: str = 'output/customers.json'):
    """Save customers to local JSON file for reference"""
    import os

    os.makedirs('output', exist_ok=True)

    with open(filename, 'w', encoding='utf-8') as f:
        json.dump(customers, f, indent=2, ensure_ascii=False)

    print(f"✓ Saved customers to {filename}")


def upload_to_dynamodb(customers: List[Dict], table_name: str, region: str):
    """
    Upload customer data to DynamoDB using batch write

    Args:
        customers: List of customer dictionaries
        table_name: DynamoDB table name
        region: AWS region
    """
    print(f"\nUploading to DynamoDB table: {table_name}")

    dynamodb = boto3.resource('dynamodb', region_name=region)
    table = dynamodb.Table(table_name)

    # Batch write items (max 25 items per batch)
    batch_size = 25
    total_uploaded = 0

    try:
        for i in range(0, len(customers), batch_size):
            batch = customers[i:i + batch_size]

            with table.batch_writer() as writer:
                for customer in batch:
                    writer.put_item(Item=customer)

            total_uploaded += len(batch)
            print(f"  Uploaded {total_uploaded}/{len(customers)} customers")

        print(
            f"✓ Successfully uploaded {total_uploaded} customers to DynamoDB")

    except ClientError as e:
        print(
            f"✗ Error uploading to DynamoDB: {e.response['Error']['Message']}")
        raise
    except Exception as e:
        print(f"✗ Unexpected error: {str(e)}")
        raise


def verify_upload(table_name: str, region: str, expected_count: int):
    """Verify that data was uploaded correctly"""
    print(f"\nVerifying upload...")

    dynamodb = boto3.resource('dynamodb', region_name=region)
    table = dynamodb.Table(table_name)

    try:
        response = table.scan(Select='COUNT')
        actual_count = response['Count']

        print(f"  Expected: {expected_count} records")
        print(f"  Actual: {actual_count} records")

        if actual_count >= expected_count:
            print(f"✓ Verification successful!")
        else:
            print(f"⚠ Warning: Found fewer records than expected")

    except ClientError as e:
        print(f"✗ Error verifying upload: {e.response['Error']['Message']}")


def main():
    """Main execution function"""
    print("=" * 60)
    print("Customer Data Generator for DynamoDB")
    print("=" * 60)

    # Load configuration
    config = load_config()
    num_customers = config.get('num_customers', 25)
    table_name = config.get('dynamodb_table', 'customer-registration-dev')
    region = config.get('aws_region', 'us-east-1')

    print(f"\nConfiguration:")
    print(f"  Number of customers: {num_customers}")
    print(f"  DynamoDB table: {table_name}")
    print(f"  AWS region: {region}")
    print()

    # Generate customer data
    customers = generate_customer_data(num_customers)

    # Save locally for reference
    save_customers_locally(customers)

    # Upload to DynamoDB
    upload_to_dynamodb(customers, table_name, region)

    # Verify upload
    verify_upload(table_name, region, num_customers)

    print("\n" + "=" * 60)
    print("Customer data generation completed!")
    print("=" * 60)

    # Display sample customer
    print("\nSample customer record:")
    print(json.dumps(customers[0], indent=2, ensure_ascii=False))


if __name__ == '__main__':
    main()
