# 🔐 Credenciais de Acesso ao OpenSearch

## 📋 Informações de Acesso

Após aplicar o Terraform, use estas credenciais para acessar o OpenSearch Dashboard:

### 🌐 URL do Dashboard

```bash
# Obter o endpoint
cd infrastructure
terraform output opensearch_kibana_endpoint
```

Acesse: `https://<endpoint>/_dashboards`

### 🔑 Credenciais Padrão

```
Usuário: admin
Senha: Admin123!@#
```

⚠️ **IMPORTANTE**: Altere a senha em produção!

---

## 🛠️ Como Obter as Credenciais

```bash
cd infrastructure

# Usuário
terraform output -raw opensearch_master_user

# Senha
terraform output -raw opensearch_master_password

# Endpoint completo
terraform output -raw opensearch_endpoint
```

---

## 🔧 Atualizar Credenciais

### Opção 1: Via terraform.tfvars

Edite `infrastructure/terraform.tfvars`:

```hcl
opensearch_master_user = "seu_usuario"
opensearch_master_password = "SuaSenhaSegura123!@#"
```

**Requisitos da senha:**

- Mínimo 8 caracteres
- Pelo menos 1 letra maiúscula
- Pelo menos 1 letra minúscula
- Pelo menos 1 número
- Pelo menos 1 caractere especial

### Opção 2: Via linha de comando

```bash
terraform apply \
  -var="opensearch_master_password=NovaSenhaSegura123!@#"
```

---

## 🔍 Acessar via API (cURL)

```bash
# Obter endpoint
ENDPOINT=$(terraform output -raw opensearch_endpoint)
USER=$(terraform output -raw opensearch_master_user)
PASS=$(terraform output -raw opensearch_master_password)

# Verificar cluster
curl -u "$USER:$PASS" "https://$ENDPOINT/_cluster/health?pretty"

# Listar índices
curl -u "$USER:$PASS" "https://$ENDPOINT/_cat/indices?v"

# Buscar documentos
curl -u "$USER:$PASS" "https://$ENDPOINT/financial-transactions/_search?pretty"
```

---

## 🐍 Acessar via Python

```python
from opensearchpy import OpenSearch

# Configuração
host = '<seu-endpoint>'
port = 443
auth = ('admin', 'Admin123!@#')

# Cliente
client = OpenSearch(
    hosts=[{'host': host, 'port': port}],
    http_auth=auth,
    use_ssl=True,
    verify_certs=True,
    ssl_show_warn=False
)

# Testar conexão
info = client.info()
print(f"OpenSearch versão: {info['version']['number']}")

# Listar índices
indices = client.cat.indices(format='json')
for idx in indices:
    print(f"Índice: {idx['index']}, Docs: {idx['docs.count']}")
```

---

## 🔧 Código Scala (Atualizar)

No arquivo `OpenSearchSink.scala`, as credenciais são passadas via argumentos do job.

**Atualizar job Glue:**

```bash
aws glue update-job \
  --job-name financial-transaction-processor \
  --job-update '{
    "DefaultArguments": {
      "--opensearch_username": "admin",
      "--opensearch_password": "Admin123!@#"
    }
  }'
```

**No código Scala**, adicione autenticação:

```scala
// No OpenSearchSink.scala
val credentialsProvider = new BasicCredentialsProvider()
credentialsProvider.setCredentials(
  AuthScope.ANY,
  new UsernamePasswordCredentials(username, password)
)

val restClientBuilder = RestClient.builder(httpHost)
  .setHttpClientConfigCallback(httpClientBuilder =>
    httpClientBuilder.setDefaultCredentialsProvider(credentialsProvider)
  )
```

---

## 📊 Verificar Dados no Dashboard

1. Acesse: `https://<endpoint>/_dashboards`
2. Login com `admin` / `Admin123!@#`
3. Menu lateral → **Stack Management** → **Index Patterns**
4. Criar pattern: `financial-transactions*`
5. Menu lateral → **Discover**
6. Visualizar documentos indexados

---

## 🔒 Segurança

### Ambiente de Desenvolvimento

- ✅ Usuário/senha padrão OK
- ✅ Access policy aberta (fine-grained control gerencia)

### Ambiente de Produção

- ⚠️ **ALTERAR** senha padrão
- ⚠️ Criar usuários específicos (não usar admin)
- ⚠️ Configurar roles e permissões granulares
- ⚠️ Restringir IPs via VPC
- ⚠️ Habilitar audit logs

---

## 🆘 Troubleshooting

### Erro: Authentication Failed

```bash
# Verificar credenciais
terraform output opensearch_master_user
terraform output opensearch_master_password

# Testar conexão
curl -u admin:Admin123!@# "https://<endpoint>/_cluster/health"
```

### Erro: Connection Timeout

```bash
# Verificar se domínio está ativo
aws opensearch describe-domain \
  --domain-name financial-txns-dev \
  --query 'DomainStatus.Processing'

# Deve retornar: false (se true, aguarde finalizar)
```

### Resetar Senha

Não é possível via Terraform após criação. Opções:

1. **Recriar domínio** (perde dados):

   ```bash
   terraform destroy -target=aws_opensearch_domain.financial_transactions
   terraform apply
   ```

2. **Via API** (se tiver acesso):
   ```bash
   aws opensearch update-domain-config \
     --domain-name financial-txns-dev \
     --advanced-security-options '{
       "MasterUserOptions": {
         "MasterUserName": "admin",
         "MasterUserPassword": "NovaSenha123!@#"
       }
     }'
   ```

---

## 📝 Checklist de Acesso

- [ ] Terraform aplicado com sucesso
- [ ] Domínio OpenSearch criado
- [ ] Obtido endpoint do dashboard
- [ ] Testado login com admin/Admin123!@#
- [ ] Dashboard carregando corretamente
- [ ] Código Scala atualizado com credenciais (se necessário)

---

**Referência Rápida:**

```bash
# Ver tudo
cd infrastructure
terraform output

# Acessar dashboard
terraform output opensearch_kibana_endpoint

# Ver credenciais
terraform output opensearch_master_user
terraform output opensearch_master_password
```
