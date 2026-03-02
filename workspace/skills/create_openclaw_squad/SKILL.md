---
name: "create_openclaw_squad"
description: "Provisiona um novo esquadrão completo de agentes em um repositório."
---

# SKILL: CREATE_OPENCLAW_SQUAD

**Responsável:** Product Agent
**Permissão:** role=product
**Trigger:** Usuário pede (no Discord) para iniciar/instalar/provisionar um novo projeto ou esquadrão em um repositório

---

## Protocolo de Execução

Quando um usuário solicitar a criação de um novo esquadrão para um projeto, você deve executar as seguintes etapas:

### 1. Extrair Parâmetros
Você precisará de 3 informações essenciais do usuário. Se alguma delas faltar no pedido original, **pergunte primeiro** antes de agir:
- **Nome do Projeto** (ex: `quemresolve-api`)
- **Repositório GitHub** (owner/repo. Ex: `barba-software/quemresolve-api`)
- **Canal do Discord** associado (apenas o nome, sem o `#`)

### 2. Auto-Instalar a Arquitetura Global
Execute o download da estrutura OpenClaw e invoque o script instalador de forma automatizada (non-interactive mode), repassando os parâmetros capturados:

```bash
# 1. Baixar a base atualizada em /tmp
git clone https://github.com/barba-software/openclaw-multiagent-system.git /tmp/openclaw-installer --quiet

# 2. Copiar as skills globais para seu workspace
mkdir -p ~/.openclaw/workspace/skills
mkdir -p ~/.openclaw/workspace/scripts
cp -R /tmp/openclaw-installer/workspace/skills/* ~/.openclaw/workspace/skills/
cp -R /tmp/openclaw-installer/workspace/scripts/* ~/.openclaw/workspace/scripts/

# 3. Executar o provisionamento (Criando as profiles e crons)
cd /tmp/openclaw-installer/workspace/scripts/
bash provision.sh "{nome_do_projeto}" "{owner/repo}" "{canal_discord}"

# Limpar arquivos temporários
rm -rf /tmp/openclaw-installer
```

### 3. Reportar Sucesso
Se o script `provision.sh` rodar sem erros (exit status 0), confirme no Discord mencionando que o novo esquadrão (Product, Developer, Reviewer e Lead) foi fabricado com sucesso e os Crons/Agentes já foram interligados ao canal designado.

---

## Nunca
- ❌ Nunca rodar essa skill sem ter a confirmação explícita do Repo e do Canal do Discord.
- ❌ Nunca usar nomes de projeto com espaços em branco (substitua por hífens).
