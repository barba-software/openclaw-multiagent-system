#!/usr/bin/env bash

set -e

PROJECT=$1
REPO=$2
DISCORD_CHANNEL_ID=$3

if [ -z "$PROJECT" ] || [ -z "$REPO" ] || [ -z "$DISCORD_CHANNEL_ID" ]; then
  echo "Uso:"
  echo "./implement-squad.sh <nome_projeto> <owner/repo> <discord_channel_id>"
  exit 1
fi

BASE_DIR="/workspace/projects/$PROJECT"

echo "🚀 Iniciando setup do projeto: $PROJECT"

# ==============================
# 1️⃣ Criar Estrutura Base
# ==============================

mkdir -p $BASE_DIR/{memory,product,developer,reviewer,lead}

# ==============================
# 2️⃣ Criar Arquivos Globais
# ==============================

if [ ! -f "$BASE_DIR/PROJECT.md" ]; then
cat <<EOF > $BASE_DIR/PROJECT.md
# PROJECT

Nome: $PROJECT
Repo: $REPO
Discord Channel ID: $DISCORD_CHANNEL_ID
Status: active
Criado em: $(date)
EOF
fi

if [ ! -f "$BASE_DIR/DISCORD.md" ]; then
cat <<EOF > $BASE_DIR/DISCORD.md
# DISCORD POLICY

Canal oficial: $DISCORD_CHANNEL_ID

Regras:
- Product interpreta demandas
- Developer não aceita tarefas diretas
- Reviewer só atua via PR
- Lead gera relatórios
EOF
fi

if [ ! -f "$BASE_DIR/GITHUB.md" ]; then
cat <<EOF > $BASE_DIR/GITHUB.md
# GITHUB POLICY

Repo: $REPO

Branch padrão:
feature/issue-XX

Sem commit direto na main.
Toda entrega via PR.
EOF
fi

if [ ! -f "$BASE_DIR/AGENTS.md" ]; then
cat <<EOF > $BASE_DIR/AGENTS.md
# AGENTS FLOW

User → Product → Issue → Developer → PR → Reviewer → Merge → Lead Report
EOF
fi

# ==============================
# 3️⃣ Criar Memória Base
# ==============================

touch $BASE_DIR/memory/MEMORY.md
touch $BASE_DIR/memory/WORKING_PRODUCT.md
touch $BASE_DIR/memory/WORKING_DEV.md
touch $BASE_DIR/memory/WORKING_REVIEW.md
touch $BASE_DIR/memory/DAILY_LOG.md

# ==============================
# 4️⃣ Criar Sessions OpenClaw
# ==============================

create_session_if_not_exists () {
  SESSION_KEY=$1
  if ! clawdbot sessions list | grep -q "$SESSION_KEY"; then
    clawdbot sessions create "$SESSION_KEY"
    echo "✔ Criada sessão $SESSION_KEY"
  else
    echo "⚠ Sessão $SESSION_KEY já existe"
  fi
}

create_session_if_not_exists "agent:$PROJECT:product"
create_session_if_not_exists "agent:$PROJECT:developer"
create_session_if_not_exists "agent:$PROJECT:reviewer"
create_session_if_not_exists "agent:$PROJECT:lead"

# ==============================
# 5️⃣ Criar Heartbeats
# ==============================

create_cron_if_not_exists () {
  CRON_NAME=$1
  CRON_SCHEDULE=$2
  MESSAGE=$3

  if ! clawdbot cron list | grep -q "$CRON_NAME"; then
    clawdbot cron add \
      --name "$CRON_NAME" \
      --cron "$CRON_SCHEDULE" \
      --session "isolated" \
      --message "$MESSAGE"
    echo "✔ Cron $CRON_NAME criado"
  else
    echo "⚠ Cron $CRON_NAME já existe"
  fi
}

create_cron_if_not_exists "$PROJECT-product-heartbeat" "*/15 * * * *" "Heartbeat product $PROJECT"
create_cron_if_not_exists "$PROJECT-developer-heartbeat" "*/15 * * * *" "Heartbeat developer $PROJECT"
create_cron_if_not_exists "$PROJECT-reviewer-heartbeat" "*/15 * * * *" "Heartbeat reviewer $PROJECT"
create_cron_if_not_exists "$PROJECT-lead-heartbeat" "0 23 * * *" "Daily standup $PROJECT"

echo ""
echo "✅ Projeto $PROJECT configurado com sucesso."
echo "Repo: $REPO"
echo "Discord Channel: $DISCORD_CHANNEL_ID"
