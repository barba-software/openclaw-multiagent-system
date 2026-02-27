#!/usr/bin/env bash

set -e

PROJECT=$1
REPO=$2
DISCORD_CHANNEL_ID=$3

if [ -z "$PROJECT" ] || [ -z "$REPO" ] || [ -z "$DISCORD_CHANNEL_ID" ]; then
  echo "Uso:"
  echo "./provision.sh <nome_projeto> <owner/repo> <discord_channel_id>"
  exit 1
fi

# ==============================
# 🔎 VALIDAÇÕES INICIAIS
# ==============================

if ! command -v gh &> /dev/null; then
  echo "❌ GitHub CLI (gh) não instalado."
  exit 1
fi

if ! command extension list gh &> /dev/null; then
  echo "❌ Github CLI extension não instalada."
  exit 1
fi

if ! command -v openclaw &> /dev/null; then
  echo "❌ OpenClaw não instalado."
  exit 1
fi

if ! gh auth status &> /dev/null; then
  echo "❌ GitHub CLI não autenticado."
  exit 1
fi

BASE_DIR="/workspace/projects/$PROJECT"
OWNER=$(echo $REPO | cut -d/ -f1)

echo "🚀 Provisionando projeto: $PROJECT"
echo ""

# ==============================
# 🛠 FUNÇÕES UTILITÁRIAS
# ==============================

create_if_missing() {
  FILE=$1
  CONTENT=$2
  if [ ! -f "$FILE" ]; then
    echo "$CONTENT" > "$FILE"
    echo "✔ Criado $FILE"
  else
    echo "⚠ $FILE já existe"
  fi
}

create_dir_if_missing() {
  DIR=$1
  if [ ! -d "$DIR" ]; then
    mkdir -p "$DIR"
    echo "✔ Criado diretório $DIR"
  else
    echo "⚠ Diretório já existe $DIR"
  fi
}

create_session_if_missing() {
  SESSION=$1
  if openclaw sessions list | grep -q "$SESSION"; then
    echo "⚠ Sessão já existe $SESSION"
  else
    openclaw sessions create "$SESSION"
    echo "✔ Sessão criada $SESSION"
  fi
}

create_cron_if_missing() {
  NAME=$1
  SCHEDULE=$2
  MESSAGE=$3

  if openclaw cron list | grep -q "$NAME"; then
    echo "⚠ Cron já existe $NAME"
  else
    openclaw cron add \
      --name "$NAME" \
      --cron "$SCHEDULE" \
      --session "isolated" \
      --message "$MESSAGE"
    echo "✔ Cron criado $NAME"
  fi
}

create_label_if_missing() {
  NAME=$1
  COLOR=$2
  DESC=$3

  if gh label list --repo "$REPO" | grep -q "^$NAME"; then
    echo "⚠ Label já existe $NAME"
  else
    gh label create "$NAME" --repo "$REPO" --color "$COLOR" --description "$DESC"
    echo "✔ Label criada $NAME"
  fi
}

# ==============================
# 📁 ESTRUTURA
# ==============================

create_dir_if_missing "$BASE_DIR"
create_dir_if_missing "$BASE_DIR/memory"
create_dir_if_missing "$BASE_DIR/product"
create_dir_if_missing "$BASE_DIR/developer"
create_dir_if_missing "$BASE_DIR/reviewer"
create_dir_if_missing "$BASE_DIR/lead"

# ==============================
# 📄 ARQUIVOS BASE
# ==============================

create_if_missing "$BASE_DIR/PROJECT.md" "Nome: $PROJECT
Repo: $REPO
Discord Channel: $DISCORD_CHANNEL_ID
Status: active
Criado em: $(date)"

create_if_missing "$BASE_DIR/AGENTS.md" "Fluxo:
User → Product → Issue → Developer → PR → Reviewer → Merge → Lead"

create_if_missing "$BASE_DIR/DISCORD.md" "Canal oficial: $DISCORD_CHANNEL_ID"
create_if_missing "$BASE_DIR/GITHUB.md" "Repo: $REPO"

create_if_missing "$BASE_DIR/memory/MEMORY.md" "# LONG TERM MEMORY"
create_if_missing "$BASE_DIR/memory/DAILY_LOG.md" "# DAILY LOG"

# ==============================
# 🤖 SESSÕES
# ==============================

create_session_if_missing "agent:$PROJECT:product"
create_session_if_missing "agent:$PROJECT:developer"
create_session_if_missing "agent:$PROJECT:reviewer"
create_session_if_missing "agent:$PROJECT:lead"

# ==============================
# ⏱ CRONS
# ==============================

create_cron_if_missing "$PROJECT-product-heartbeat" "*/15 * * * *" "Heartbeat product $PROJECT"
create_cron_if_missing "$PROJECT-developer-heartbeat" "*/15 * * * *" "Heartbeat developer $PROJECT"
create_cron_if_missing "$PROJECT-reviewer-heartbeat" "*/15 * * * *" "Heartbeat reviewer $PROJECT"
create_cron_if_missing "$PROJECT-standup" "0 23 * * *" "Daily standup $PROJECT"

# ==============================
# 🔖 LABELS
# ==============================

echo ""
echo "Criando labels..."

create_label_if_missing "inbox" "ededed" "Nova tarefa"
create_label_if_missing "in_progress" "0052cc" "Em desenvolvimento"
create_label_if_missing "review" "fbca04" "Em revisão"
create_label_if_missing "blocked" "d93f0b" "Bloqueado"
create_label_if_missing "done" "0e8a16" "Concluído"

create_label_if_missing "agent:product" "5319e7" "Responsável Product"
create_label_if_missing "agent:developer" "1d76db" "Responsável Developer"
create_label_if_missing "agent:reviewer" "c2e0c6" "Responsável Reviewer"

# ==============================
# 📊 PROJECT BOARD + STATUS COLUMNS
# ==============================

echo ""
echo "📊 Configurando Project Board..."

BOARD_NAME="$PROJECT Board"

# Criar board se não existir
BOARD_ID=$(gh project list --owner "$OWNER" --format json | jq -r ".[] | select(.title==\"$BOARD_NAME\") | .id")

if [ -z "$BOARD_ID" ]; then
  echo "Criando novo Project Board..."
  gh project create --owner "$OWNER" --title "$BOARD_NAME" > /dev/null
  BOARD_ID=$(gh project list --owner "$OWNER" --format json | jq -r ".[] | select(.title==\"$BOARD_NAME\") | .id")
  echo "✔ Board criado"
else
  echo "⚠ Board já existe"
fi

# Verificar se campo Status existe
STATUS_FIELD_ID=$(gh project field-list "$BOARD_ID" --format json | jq -r ".[] | select(.name==\"Status\") | .id")

if [ -z "$STATUS_FIELD_ID" ]; then
  echo "Criando campo Status..."
  gh project field-create "$BOARD_ID" \
    --name "Status" \
    --data-type SINGLE_SELECT > /dev/null

  STATUS_FIELD_ID=$(gh project field-list "$BOARD_ID" --format json | jq -r ".[] | select(.name==\"Status\") | .id")
  echo "✔ Campo Status criado"
else
  echo "⚠ Campo Status já existe"
fi

# Função para criar opção de status se não existir
create_status_option_if_missing () {
  OPTION_NAME=$1

  if gh project field-list "$BOARD_ID" --format json | jq -e ".[] | select(.name==\"Status\") | .options[] | select(.name==\"$OPTION_NAME\")" > /dev/null; then
    echo "⚠ Status já existe: $OPTION_NAME"
  else
    gh project field-option-create "$BOARD_ID" \
      --field-id "$STATUS_FIELD_ID" \
      --name "$OPTION_NAME" > /dev/null
    echo "✔ Status criado: $OPTION_NAME"
  fi
}

echo ""
echo "Criando colunas de status..."

create_status_option_if_missing "Inbox"
create_status_option_if_missing "In Progress"
create_status_option_if_missing "Review"
create_status_option_if_missing "Blocked"
create_status_option_if_missing "Done"

echo "✔ Colunas configuradas com sucesso"

# ==============================
# 📦 REGISTRY GLOBAL
# ==============================

REGISTRY="/workspace/registry.json"

if [ ! -f "$REGISTRY" ]; then
  echo "[]" > "$REGISTRY"
fi

if ! grep -q "\"$PROJECT\"" "$REGISTRY"; then
  tmp=$(mktemp)
  jq ". += [{\"project\":\"$PROJECT\",\"repo\":\"$REPO\",\"discord\":\"$DISCORD_CHANNEL_ID\"}]" "$REGISTRY" > "$tmp"
  mv "$tmp" "$REGISTRY"
  echo "✔ Registrado no registry.json"
else
  echo "⚠ Projeto já registrado"
fi

echo ""
echo "✅ Provisionamento completo finalizado."
