# 🚀 Guia de Configuração AWS e Execução do Dry-Run

## 📋 Informações da Conta AWS

- **Console URL**: https://160885283918.signin.aws.amazon.com/console
- **Usuário**: thmileo@brq.com
- **Senha**: YmrM16\*N
- **Account ID**: 160885283918
- **Região**: us-east-2 (Ohio)

## 🔑 Passo 1: Gerar Access Keys no Console AWS

1. Acesse o Console AWS: https://160885283918.signin.aws.amazon.com/console
2. Faça login com:
   - User: `thmileo@brq.com`
   - Password: `YmrM16*N`

3. No console, vá para: **IAM** → **Users** → **thmileo@brq.com**

4. Clique na aba **Security credentials**

5. Na seção **Access keys**, clique em **Create access key**

6. Selecione o caso de uso: **Command Line Interface (CLI)**

7. Marque a confirmação e clique em **Next**

8. (Opcional) Adicione uma descrição: "Terraform Local Development"

9. Clique em **Create access key**

10. ⚠️ **IMPORTANTE**: Salve em local seguro:
    - **Access Key ID**: (exemplo: AKIAIOSFODNN7EXAMPLE)
    - **Secret Access Key**: (exemplo: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY)

## 🛠️ Passo 2: Configurar AWS CLI

Execute no terminal:

```bash
aws configure
```

Quando solicitado, insira:

```
AWS Access Key ID [None]: [Cole aqui seu Access Key ID]
AWS Secret Access Key [None]: [Cole aqui seu Secret Access Key]
Default region name [None]: us-east-2
Default output format [None]: json
```

## ✅ Passo 3: Validar Credenciais

Teste se as credenciais estão funcionando:

```bash
aws sts get-caller-identity
```

Você deve ver algo como:

```json
{
  "UserId": "AIDAXXXXXXXXXXXXXX",
  "Account": "160885283918",
  "Arn": "arn:aws:iam::160885283918:user/thmileo@brq.com"
}
```

## 🏗️ Passo 4: Executar Terraform Dry-Run (Plan)

Navegue até o diretório de infraestrutura:

```bash
cd /home/thiagohmm/Estudo/dryRun/infrastructure
```

Execute o Terraform plan (dry-run):

```bash
terraform plan
```

Isso mostrará todos os recursos que serão criados **SEM** realmente criá-los.

## 📦 Recursos que serão criados:

1. **S3 Buckets** (2):
   - `financial-transactions-dev-160885283918` - armazenamento de transações
   - `glue-scripts-dev-160885283918` - scripts do Glue job

2. **DynamoDB Table**:
   - `customer-registration-dev` - dados de clientes

3. **OpenSearch Domain**:
   - `financial-txns-dev` - busca e analytics

4. **AWS Glue Job**:
   - `financial-transaction-processor` - processamento batch

5. **IAM Roles e Policies** - permissões necessárias

## 🚀 Passo 5: Aplicar a Infraestrutura (Opcional)

Se o plan estiver correto e você quiser criar os recursos:

```bash
terraform apply
```

Digite `yes` quando solicitado.

## 🧹 Destruir Recursos (Quando terminar)

Para remover toda a infraestrutura criada:

```bash
terraform destroy
```

## 📝 Arquivos Atualizados

- ✅ `variables.tf` - região alterada para `us-east-2`
- ✅ `terraform.tfvars` - configurações específicas da conta
- ✅ `.gitignore` - proteção de arquivos sensíveis
- ✅ `AWS_CREDENTIALS.md` - guia de credenciais (não commitado)

## ⚠️ Importante

- **NÃO** commite as Access Keys no git
- O arquivo `terraform.tfvars` já está no `.gitignore`
- Mantenha suas credenciais em local seguro
- Após os testes, considere desativar ou deletar as Access Keys
