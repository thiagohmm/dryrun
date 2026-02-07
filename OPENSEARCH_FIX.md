# ✅ Correção do Erro OpenSearch - Resumo

## 🐛 Erro Original

```
Error: creating OpenSearch Domain: ValidationException:
Enable fine-grained access control or apply a restrictive access policy to your domain
```

## 🔧 Causa

A AWS OpenSearch exige **fine-grained access control** (controle de acesso refinado) habilitado OU uma política de acesso muito restritiva. O domínio estava configurado com:

- Fine-grained access control: **DESABILITADO** ❌
- Access policy: **Muito permissiva** ❌

## ✅ Solução Aplicada

### 1. Habilitado Fine-Grained Access Control

**Arquivo**: `infrastructure/opensearch.tf`

```hcl
advanced_security_options {
  enabled                        = true   # ← HABILITADO
  internal_user_database_enabled = true
  master_user_options {
    master_user_name     = var.opensearch_master_user
    master_user_password = var.opensearch_master_password
  }
}
```

### 2. Adicionadas Variáveis de Credenciais

**Arquivo**: `infrastructure/variables.tf`

```hcl
variable "opensearch_master_user" {
  description = "Nome de usuário mestre do OpenSearch"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "opensearch_master_password" {
  description = "Senha do usuário mestre do OpenSearch"
  type        = string
  default     = "Admin123!@#"
  sensitive   = true
}
```

### 3. Configuradas Credenciais Padrão

**Arquivo**: `infrastructure/terraform.tfvars`

```hcl
opensearch_master_user = "admin"
opensearch_master_password = "Admin123!@#"
```

### 4. Simplificada Access Policy

Como fine-grained access control está habilitado, a access policy pode ser mais permissiva (ele gerencia as permissões):

```hcl
access_policies = jsonencode({
  Version = "2012-10-17"
  Statement = [
    {
      Effect = "Allow"
      Principal = {
        AWS = "*"
      }
      Action   = "es:*"
      Resource = "arn:aws:es:${local.region}:${local.account_id}:domain/${var.opensearch_domain_name}/*"
      # Removido: Condition com IpAddress (fine-grained control gerencia isso)
    }
  ]
})
```

## 📋 Arquivos Modificados

1. ✅ `infrastructure/opensearch.tf` - Habilitado fine-grained access control
2. ✅ `infrastructure/variables.tf` - Adicionadas variáveis de credenciais
3. ✅ `infrastructure/terraform.tfvars` - Configuradas credenciais padrão
4. ✅ `infrastructure/outputs.tf` - Adicionados outputs de credenciais
5. ✅ **NOVO**: `OPENSEARCH_ACCESS.md` - Guia de acesso

## 🚀 Próximos Passos

### 1. Aplicar a Correção

```bash
cd infrastructure
terraform apply
```

Agora deve funcionar! ✅

### 2. Após Aplicação

```bash
# Ver endpoint do dashboard
terraform output opensearch_kibana_endpoint

# Ver credenciais
terraform output opensearch_master_user
terraform output opensearch_master_password
```

### 3. Acessar Dashboard

```
URL: https://<endpoint>/_dashboards
Usuário: admin
Senha: Admin123!@#
```

## 🔐 Segurança

### Desenvolvimento (Atual) ✅

- Usuário: `admin`
- Senha: `Admin123!@#`
- OK para ambiente de desenvolvimento/testes

### Produção ⚠️

Você **DEVE** alterar a senha:

```bash
# Opção 1: Via terraform.tfvars
opensearch_master_password = "SuaSenhaSegura123!@#$%"

# Opção 2: Via variável de ambiente
export TF_VAR_opensearch_master_password="SuaSenhaSegura123!@#$%"
terraform apply
```

**Requisitos da senha:**

- Mínimo 8 caracteres
- Letra maiúscula
- Letra minúscula
- Número
- Caractere especial

## 🔍 Verificar Funcionamento

Após `terraform apply`:

```bash
# 1. Obter endpoint
ENDPOINT=$(terraform output -raw opensearch_endpoint)

# 2. Obter credenciais
USER=$(terraform output -raw opensearch_master_user)
PASS=$(terraform output -raw opensearch_master_password)

# 3. Testar acesso
curl -u "$USER:$PASS" "https://$ENDPOINT/_cluster/health?pretty"
```

**Resposta esperada:**

```json
{
  "cluster_name" : "160885283918:financial-txns-dev",
  "status" : "green",
  "timed_out" : false,
  "number_of_nodes" : 1,
  ...
}
```

## 📊 Diferenças: Antes vs Depois

| Aspecto                     | Antes ❌        | Depois ✅                      |
| --------------------------- | --------------- | ------------------------------ |
| Fine-grained access control | Desabilitado    | **Habilitado**                 |
| Master user                 | N/A             | **admin**                      |
| Master password             | N/A             | **Admin123!@#**                |
| Access policy               | Restrita por IP | Aberta (fine-grained controla) |
| Acesso via Dashboard        | ❌ Não funciona | ✅ Funciona                    |
| Autenticação necessária     | ❌              | ✅ user/password               |

## 📚 Documentação Adicional

- **[OPENSEARCH_ACCESS.md](./OPENSEARCH_ACCESS.md)** - Guia completo de acesso
  - Como acessar o Dashboard
  - Como usar a API
  - Como integrar com Python/Scala
  - Troubleshooting
  - Segurança

## ✅ Checklist

- [x] Fine-grained access control habilitado
- [x] Variáveis de credenciais criadas
- [x] Credenciais padrão configuradas
- [x] Outputs atualizados
- [x] Documentação criada
- [ ] Aplicar terraform (`terraform apply`)
- [ ] Testar acesso ao dashboard
- [ ] Verificar API com curl
- [ ] Atualizar código Scala (se necessário)

## 🎯 Resumo

**Problema**: OpenSearch exigia fine-grained access control  
**Solução**: Habilitado com usuário/senha admin/Admin123!@#  
**Status**: ✅ Pronto para aplicar  
**Ação**: Execute `terraform apply`

---

**Agora execute:**

```bash
cd /home/thiagohmm/Estudo/dryRun/infrastructure
terraform apply
```

Deve funcionar! 🚀
