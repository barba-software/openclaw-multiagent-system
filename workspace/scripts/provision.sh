#!/usr/bin/env bash
# =============================================================================
# provision.sh — Provisiona um projeto completo no OpenClaw
# =============================================================================
# Uso: provision.sh <project> <repo> <channel> <guild_id> [channel_id] [dev_thread_id] [review_thread_id] [lead_thread_id]
#
# Cria: workspaces, agentes, crons, labels, board+colunas, clone do repo
# Se channel_id e threads NÃO forem informados, tenta criar via Discord API
# =============================================================================

set -euo pipefail

PROJECT="${1:-}"
REPO="${2:-}"
DISCORD_CHANNEL="${3:-}"
DISCORD_GUILD_ID="${4:-}"
CHANNEL_ID="${5:-}"
DEV_THREAD_ID="${6:-}"
REVIEW_THREAD_ID="${7:-}"
LEAD_THREAD_ID="${8:-}"
LABELS_ONLY="${LABELS_ONLY:-false}"

if [ -z "$PROJECT" ] || [ -z "$REPO" ] || [ -z "$DISCORD_CHANNEL" ] || [ -z "$DISCORD_GUILD_ID" ]; then
  echo "Uso: provision.sh <project> <repo> <channel> <guild_id> [channel_id] [dev_thread_id] [review_thread_id] [lead_thread_id]"
  echo ""
  echo "Variáveis opcionais:"
  echo "  LABELS_ONLY=true   → apenas recria labels (skip agentes/crons/board)"
  exit 1
fi

DISCORD_CHANNEL="${DISCORD_CHANNEL#\#}"
OWNER=$(echo "$REPO" | cut -d/ -f1)
BASE_DIR="$HOME/.openclaw/workspace/projects/$PROJECT"
AGENT_WS_BASE="$BASE_DIR/agents"
CONFIG_FILE="$HOME/.openclaw/openclaw.json"
LOCAL_AGENTS_DIR="$HOME/.openclaw/workspace/agents"
NOW=$(date -Iseconds)

echo "🚀 Provisionando: $PROJECT"
echo "   repo:    $REPO"
echo "   channel: #$DISCORD_CHANNEL (guild: $DISCORD_GUILD_ID)"
echo ""

ok()   { echo " ✔ $1"; }
warn() { echo " ⚠ $1"; }
fail() { echo " ❌ $1"; exit 1; }

# =============================================================================
# 0. LABELS ONLY — modo de reconfiguração rápida
# =============================================================================
if [ "$LABELS_ONLY" = "true" ]; then
  echo "[ Labels only ]"
  _create_label() {
    local name=$1 color=$2 desc=$3
    gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" 2>/dev/null \
      || gh label edit "$name" --repo "$REPO" --color "$color" --description "$desc" 2>/dev/null \
      || true
  }
  _create_label "inbox"       "0075ca" "Issue criada, aguardando atribuição"
  _create_label "in_progress" "e4e669" "Em desenvolvimento"
  _create_label "review"      "d93f0b" "Aguardando revisão"
  _create_label "blocked"     "b60205" "Bloqueada — precisa de atenção"
  _create_label "done"        "0e8a16" "Concluída"
  _create_label "agent:product"   "f9d0c4" "Responsabilidade: Product"
  _create_label "agent:developer" "c2e0c6" "Responsabilidade: Developer"
  _create_label "agent:reviewer"  "bfd4f2" "Responsabilidade: Reviewer"
  ok "Labels recriadas"
  exit 0
fi

# =============================================================================
# 1. DISCORD — criar canal e threads via API (se IDs não informados)
# =============================================================================
echo "[ Discord ]"

_discord_api() {
  local method=$1 path=$2 data=$3
  local token
  token=$(jq -r '.channels.discord.token // empty' "$CONFIG_FILE" 2>/dev/null || true)
  [ -z "$token" ] && token="${DISCORD_BOT_TOKEN:-}"
  [ -z "$token" ] && { warn "DISCORD_BOT_TOKEN não encontrado — Discord API não disponível"; return 1; }
  curl -s -X "$method" "https://discord.com/api/v10$path" \
    -H "Authorization: Bot $token" \
    -H "Content-Type: application/json" \
    -d "$data"
}

# Criar ou encontrar canal de texto
if [ -z "$CHANNEL_ID" ]; then
  echo "  Verificando canal #$DISCORD_CHANNEL..."
  CHANNELS=$(_discord_api GET "/guilds/$DISCORD_GUILD_ID/channels" "" 2>/dev/null || true)
  CHANNEL_ID=$(echo "$CHANNELS" | jq -r --arg n "$DISCORD_CHANNEL" '.[] | select(.name==$n and .type==0) | .id' 2>/dev/null | head -1 || true)
  if [ -z "$CHANNEL_ID" ]; then
    echo "  Canal não encontrado — criando #$DISCORD_CHANNEL..."
    CHAN_RESULT=$(_discord_api POST "/guilds/$DISCORD_GUILD_ID/channels" \
      "{\"name\":\"$DISCORD_CHANNEL\",\"type\":0}" 2>/dev/null || true)
    CHANNEL_ID=$(echo "$CHAN_RESULT" | jq -r '.id // empty' 2>/dev/null || true)
  fi
  [ -n "$CHANNEL_ID" ] && ok "Canal #$DISCORD_CHANNEL: $CHANNEL_ID" \
    || warn "Não foi possível criar/encontrar canal #$DISCORD_CHANNEL — informe CHANNEL_ID manualmente"
else
  ok "Canal (informado): $CHANNEL_ID"
fi

# Busca thread ativa por nome; cria apenas se não encontrar
_find_or_create_thread() {
  local name=$1
  local id active_result
  active_result=$(_discord_api GET "/channels/$CHANNEL_ID/threads/active" "" 2>/dev/null || true)
  id=$(echo "$active_result" | jq -r --arg n "$name" '.threads[]? | select(.name==$n) | .id' 2>/dev/null | head -1 || true)
  if [ -z "$id" ]; then
    local result
    result=$(_discord_api POST "/channels/$CHANNEL_ID/threads" \
      "{\"name\":\"$name\",\"type\":11,\"auto_archive_duration\":10080}" 2>/dev/null || true)
    id=$(echo "$result" | jq -r '.id // empty' 2>/dev/null || true)
  fi
  echo "$id"
}

if [ -n "$CHANNEL_ID" ]; then
  if [ -z "$DEV_THREAD_ID" ]; then
    DEV_THREAD_ID=$(_find_or_create_thread "${PROJECT}-dev")
    [ -n "$DEV_THREAD_ID" ] && ok "Thread ${PROJECT}-dev: $DEV_THREAD_ID" \
      || warn "Não foi possível criar thread ${PROJECT}-dev — informe DEV_THREAD_ID manualmente"
  else
    ok "Thread dev (informada): $DEV_THREAD_ID"
  fi

  if [ -z "$REVIEW_THREAD_ID" ]; then
    REVIEW_THREAD_ID=$(_find_or_create_thread "${PROJECT}-review")
    [ -n "$REVIEW_THREAD_ID" ] && ok "Thread ${PROJECT}-review: $REVIEW_THREAD_ID" \
      || warn "Não foi possível criar thread ${PROJECT}-review — informe REVIEW_THREAD_ID manualmente"
  else
    ok "Thread review (informada): $REVIEW_THREAD_ID"
  fi

  if [ -z "$LEAD_THREAD_ID" ]; then
    LEAD_THREAD_ID=$(_find_or_create_thread "${PROJECT}-lead")
    [ -n "$LEAD_THREAD_ID" ] && ok "Thread ${PROJECT}-lead: $LEAD_THREAD_ID" \
      || warn "Não foi possível criar thread ${PROJECT}-lead — informe LEAD_THREAD_ID manualmente"
  else
    ok "Thread lead (informada): $LEAD_THREAD_ID"
  fi
fi
echo ""

# =============================================================================
# 2. ESTRUTURA DE DIRETÓRIOS
# =============================================================================
echo "[ Estrutura ]"
mkdir -p "$BASE_DIR/memory"/{product,developer,reviewer,lead}
mkdir -p "$BASE_DIR/agents"
ok "Diretórios criados"
echo ""

# =============================================================================
# 3. WORKSPACES DOS AGENTES
# =============================================================================
echo "[ Workspaces ]"

setup_ws() {
  local role=$1 name=$2
  local ws="$AGENT_WS_BASE/$role"
  mkdir -p "$ws"
  for doc in IDENTITY.md SOUL.md AGENTS.md HEARTBEAT.md USER.md WORKING.md; do
    local src="$LOCAL_AGENTS_DIR/$role/$doc"
    local dst="$ws/$doc"
    [ -f "$src" ] || fail "Template ausente: $src"
    if [ ! -f "$dst" ]; then
      sed -e "s/{{PROJECT}}/$PROJECT/g" \
          -e "s/{{REPO}}/$REPO/g" \
          -e "s/{{DISCORD_CHANNEL}}/$DISCORD_CHANNEL/g" \
          -e "s/{{DISCORD_GUILD_ID}}/$DISCORD_GUILD_ID/g" \
          -e "s/{{CHANNEL_ID}}/${CHANNEL_ID:-}/g" \
          -e "s/{{DEV_THREAD_ID}}/${DEV_THREAD_ID:-}/g" \
          -e "s/{{REVIEW_THREAD_ID}}/${REVIEW_THREAD_ID:-}/g" \
          -e "s/{{LEAD_THREAD_ID}}/${LEAD_THREAD_ID:-}/g" \
          -e "s/{{NAME}}/$name/g" "$src" > "$dst"
    fi
    [ "$doc" = "IDENTITY.md" ] && mkdir -p "$ws/.template" && cp "$dst" "$ws/.template/IDENTITY.md"
  done
  # Gravar SKILL_PATH no WORKING.md para referência rápida
  if ! grep -q "SKILL_PATH" "$ws/WORKING.md" 2>/dev/null; then
    printf '\n---\nSKILL_PATH: %s\nSCRIPTS_PATH: %s\n' \
      "$HOME/.openclaw/workspace/skills" \
      "$HOME/.openclaw/workspace/scripts" >> "$ws/WORKING.md"
  fi
  ok "workspace: $role"
}

for role in product developer reviewer lead; do
  setup_ws "$role" "$PROJECT $role"
done

# Criar LESSONS.md por agente (memória persistente de aprendizado)
for role in product developer reviewer lead; do
  LESSONS_FILE="$BASE_DIR/agents/$role/LESSONS.md"
  if [ ! -f "$LESSONS_FILE" ]; then
    mkdir -p "$(dirname "$LESSONS_FILE")"
    cat > "$LESSONS_FILE" << LESSONS
# LESSONS — $PROJECT $role
> Lições aprendidas em ciclos anteriores. Máximo 30 entradas — as mais antigas são removidas automaticamente.
> Formato: ## [YYYY-MM-DD] {contexto} / Erro-Causa-Lição-Ação

LESSONS
    ok "LESSONS.md: $role"
  else
    ok "LESSONS.md já existe: $role"
  fi
done
echo ""

# =============================================================================
# 4. AGENTES + BINDINGS
# =============================================================================
echo "[ Agentes ]"

add_binding() {
  local agent=$1 peer=$2 kind=${3:-channel}
  local tmp
  tmp=$(mktemp)
  jq "del(.bindings[] | select(.agentId == \"$agent\"))" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
  jq ".bindings += [{\"agentId\": \"$agent\", \"match\": {\"channel\": \"discord\", \"peer\": {\"kind\": \"channel\", \"id\": \"$peer\"}}}]" \
    "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
  ok "bind: $agent → $peer ($kind)"
}

add_guild() {
  local guild=$1 chan=$2 name=$3
  local tmp
  tmp=$(mktemp)
  jq ".channels.discord.guilds[\"$guild\"].channels[\"$chan\"] = {\"allow\": true, \"requireMention\": false}" \
    "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
}

create_agent() {
  local role=$1 agent="${PROJECT}-$role" ws="$AGENT_WS_BASE/$role"
  openclaw agents delete "$agent" --force 2>/dev/null || true
  jq "del(.agents.list[] | select(.id == \"$agent\"))" "$CONFIG_FILE" 2>/dev/null > /tmp/jqtmp \
    && mv /tmp/jqtmp "$CONFIG_FILE" 2>/dev/null || true
  openclaw agents add "$agent" --workspace "$ws" || fail "agents add: $agent"
  openclaw agents set-identity --workspace "$ws" --from-identity 2>/dev/null || true

  case "$role" in
    product)
      [ -n "$CHANNEL_ID" ] && add_binding "$agent" "$CHANNEL_ID" channel \
        && add_guild "$DISCORD_GUILD_ID" "$CHANNEL_ID" "$DISCORD_CHANNEL"
      ;;
    developer)
      [ -n "$DEV_THREAD_ID" ] && add_binding "$agent" "$DEV_THREAD_ID" thread \
        && add_guild "$DISCORD_GUILD_ID" "$DEV_THREAD_ID" "${PROJECT}-dev"
      ;;
    reviewer)
      [ -n "$REVIEW_THREAD_ID" ] && add_binding "$agent" "$REVIEW_THREAD_ID" thread \
        && add_guild "$DISCORD_GUILD_ID" "$REVIEW_THREAD_ID" "${PROJECT}-review"
      ;;
    lead)
      [ -n "$LEAD_THREAD_ID" ] && add_binding "$agent" "$LEAD_THREAD_ID" thread \
        && add_guild "$DISCORD_GUILD_ID" "$LEAD_THREAD_ID" "${PROJECT}-lead"
      ;;
  esac
  ok "agente: $agent"
}

for role in product developer reviewer lead; do
  create_agent "$role"
done
echo ""

# =============================================================================
# 5. CRONS
# =============================================================================
echo "[ Crons ]"

# sched_flag: --every | --cron
# sched_val:  15m     | "0 23 * * *"
create_cron() {
  local name=$1 agent=$2 sched_flag=$3 sched_val=$4 msg=$5
  # Remove entrada anterior garantindo idempotência (sem loop — delete é no-op se não existir)
  openclaw cron delete "$name" 2>/dev/null || true
  openclaw cron add --name "$name" --agent "$agent" "$sched_flag" "$sched_val" \
    --session isolated --message "$msg" --exec full --no-deliver 2>/dev/null \
    && ok "cron: $name" \
    || warn "cron $name — falha ao criar (crie manualmente se necessário)"
}

# ── Product: REATIVO via Discord binding (sem cron) ──
# O Product Agent responde em tempo real às mensagens no canal #{{DISCORD_CHANNEL}}.
# Ele é acordado automaticamente pelo binding do OpenClaw — não precisa de cron.
# Um cron de segurança a cada 2h verifica pendências não processadas.
create_cron "${PROJECT}-product-hb"     "${PROJECT}-product"   "--every" "2h"         "HEARTBEAT (EXEC FULL): Leia e execute COMPLETAMENTE (todos os passos, sem pular nenhuma etapa) seu arquivo HEARTBEAT.md em ~/.openclaw/workspace/projects/${PROJECT}/agents/product/HEARTBEAT.md — SOMENTE execute ações descritas neste arquivo e no AGENTS.md"

# ── Developer: cron de segurança (30 min) ──
# O Developer é acordado via 'openclaw send' pelo state_engine quando uma issue é atribuída.
# O cron funciona apenas como safety net para retomar trabalho interrompido (WORKING.md).
create_cron "${PROJECT}-dev-hb"         "${PROJECT}-developer" "--every" "30m"        "HEARTBEAT (EXEC FULL): Leia e execute COMPLETAMENTE (todos os passos, sem pular nenhuma etapa) seu arquivo HEARTBEAT.md em ~/.openclaw/workspace/projects/${PROJECT}/agents/developer/HEARTBEAT.md — PRIORIDADE: PRs com mudanças solicitadas > issues em andamento > novas issues — SOMENTE execute ações descritas neste arquivo e no AGENTS.md"

# ── Reviewer: REATIVO via openclaw send (sem cron de polling) ──
# O Reviewer é acordado pelo state_engine no evento 'pr_created' via 'openclaw send'.
# Um cron de segurança a cada 2h verifica PRs pendentes não processadas.
create_cron "${PROJECT}-review-hb"      "${PROJECT}-reviewer"  "--every" "2h"         "HEARTBEAT (EXEC FULL): Leia e execute COMPLETAMENTE (todos os passos, sem pular nenhuma etapa) seu arquivo HEARTBEAT.md em ~/.openclaw/workspace/projects/${PROJECT}/agents/reviewer/HEARTBEAT.md — SOMENTE execute ações descritas neste arquivo e no AGENTS.md"

# ── Lead: crons de monitoramento ──
create_cron "${PROJECT}-lead-standup"   "${PROJECT}-lead"      "--cron"  "0 23 * * *" "STANDUP (EXEC FULL): Leia e execute COMPLETAMENTE a seção 'Diário às 23h00' do seu HEARTBEAT.md em ~/.openclaw/workspace/projects/${PROJECT}/agents/lead/HEARTBEAT.md — SOMENTE execute ações descritas neste arquivo e no AGENTS.md"
create_cron "${PROJECT}-lead-reconcile" "${PROJECT}-lead"      "--every" "30m"        "RECONCILE (EXEC FULL): Execute a skill RECONCILE_STATE completamente. Leia os detalhes em ~/.openclaw/workspace/skills/reconcile_state/SKILL.md — SOMENTE execute ações descritas no AGENTS.md e HEARTBEAT.md"
create_cron "${PROJECT}-lead-watchdog"  "${PROJECT}-lead"      "--every" "15m"        "WATCHDOG (EXEC FULL): Leia e execute COMPLETAMENTE a seção 'No ciclo de monitoramento (15 min)' do seu HEARTBEAT.md em ~/.openclaw/workspace/projects/${PROJECT}/agents/lead/HEARTBEAT.md — SOMENTE execute ações descritas neste arquivo e no AGENTS.md"
echo ""

# =============================================================================
# 6. LABELS
# =============================================================================
echo "[ Labels ]"
LABELS_ONLY=true "$0" "$PROJECT" "$REPO" "$DISCORD_CHANNEL" "$DISCORD_GUILD_ID" 2>/dev/null || {
  # Fallback inline se chamada recursiva falhar
  for label in inbox in_progress review blocked done; do
    gh label create "$label" --repo "$REPO" --color "ededed" 2>/dev/null || true
  done
  for label in "agent:product" "agent:developer" "agent:reviewer"; do
    gh label create "$label" --repo "$REPO" --color "f9d0c4" 2>/dev/null || true
  done
}
echo ""

# =============================================================================
# 7. BOARD + COLUNAS (Status options corretas)
# =============================================================================
echo "[ GitHub Board ]"

BOARD_NAME="$PROJECT Board"
OWNER_NODE_ID=$(gh api "orgs/$OWNER" --jq .node_id 2>/dev/null \
  || gh api "users/$OWNER" --jq .node_id 2>/dev/null || true)

if [ -z "$OWNER_NODE_ID" ]; then
  warn "Não foi possível obter node_id do owner $OWNER — board não criado automaticamente"
else
  # Verificar se board já existe
  BOARD_ID=$(gh api graphql -f query="
    query {
      node(id: \"$OWNER_NODE_ID\") {
        ... on User         { projectsV2(first:20) { nodes { id title closed } } }
        ... on Organization { projectsV2(first:20) { nodes { id title closed } } }
      }
    }
  " 2>/dev/null | jq -r ".data.node.projectsV2.nodes[] | select(.title==\"$BOARD_NAME\" and .closed==false) | .id" | head -1 || true)

  if [ -z "$BOARD_ID" ]; then
    echo "  Criando board '$BOARD_NAME'..."
    # gh project create retorna a URL do board
    BOARD_URL=$(gh project create --owner "$OWNER" --title "$BOARD_NAME" --format json 2>/dev/null \
      | jq -r '.url // empty' || true)
    sleep 2
    # Obter ID do board recém-criado
    BOARD_ID=$(gh api graphql -f query="
      query {
        node(id: \"$OWNER_NODE_ID\") {
          ... on User         { projectsV2(first:20) { nodes { id title closed } } }
          ... on Organization { projectsV2(first:20) { nodes { id title closed } } }
        }
      }
    " 2>/dev/null | jq -r ".data.node.projectsV2.nodes[] | select(.title==\"$BOARD_NAME\" and .closed==false) | .id" | head -1 || true)
    [ -n "$BOARD_ID" ] && ok "Board criado: $BOARD_NAME" || warn "Board não encontrado após criação"
  else
    ok "Board já existe: $BOARD_NAME"
  fi

  # Criar/verificar colunas Status com os nomes corretos
  if [ -n "$BOARD_ID" ]; then
    echo "  Configurando colunas Status..."

    # Obter Status field ID e options existentes
    STATUS_FIELD=$(gh api graphql -f query="
      query {
        node(id: \"$BOARD_ID\") {
          ... on ProjectV2 {
            fields(first: 20) {
              nodes {
                ... on ProjectV2SingleSelectField { id name options { id name } }
              }
            }
          }
        }
      }
    " 2>/dev/null || true)

    STATUS_FIELD_ID=$(echo "$STATUS_FIELD" | jq -r '.data.node.fields.nodes[] | select(.name=="Status") | .id' 2>/dev/null | head -1 || true)

    if [ -n "$STATUS_FIELD_ID" ]; then
      # Verificar quais options já existem
      EXISTING_OPTIONS=$(echo "$STATUS_FIELD" | jq -r '.data.node.fields.nodes[] | select(.name=="Status") | .options[].name' 2>/dev/null || true)

      for col in "Inbox" "In Progress" "Review" "Blocked" "Done"; do
        if ! echo "$EXISTING_OPTIONS" | grep -qx "$col"; then
          gh api graphql -f query="
            mutation {
              updateProjectV2Field(input: {
                projectId: \"$BOARD_ID\"
                fieldId: \"$STATUS_FIELD_ID\"
                singleSelectOptionInput: { name: \"$col\", color: GRAY, description: \"\" }
              }) { projectV2Field { id } }
            }
          " &>/dev/null || true
          ok "Coluna criada: $col"
        else
          ok "Coluna já existe: $col"
        fi
      done
    else
      warn "Campo Status não encontrado — configure as colunas manualmente: Inbox, In Progress, Review, Blocked, Done"
    fi
  fi
fi
echo ""

# =============================================================================
# 8. CLONE DO REPOSITÓRIO
# =============================================================================
echo "[ Repositório ]"
REPO_DIR="$BASE_DIR/repo"
if [ ! -d "$REPO_DIR/.git" ]; then
  echo "  Clonando $REPO..."
  git clone "https://github.com/$REPO.git" "$REPO_DIR" --quiet \
    && ok "Repositório clonado em $REPO_DIR" \
    || warn "Clone falhou — configure GH_TOKEN ou SSH. Developer não conseguirá commitar."
else
  echo "  Atualizando repositório..."
  cd "$REPO_DIR" && git pull --quiet && ok "Repositório atualizado" || warn "git pull falhou"
fi
echo ""

# =============================================================================
# 9. STATE.JSON INICIAL
# =============================================================================
echo "[ State ]"
STATE_FILE="$BASE_DIR/state.json"
if [ ! -f "$STATE_FILE" ]; then
  cat > "$STATE_FILE" << STATE
{
  "project": "$PROJECT",
  "repo": "$REPO",
  "discord": {
    "guild_id": "$DISCORD_GUILD_ID",
    "channel": "${CHANNEL_ID:-}",
    "threads": {
      "dev": "${DEV_THREAD_ID:-}",
      "review": "${REVIEW_THREAD_ID:-}",
      "lead": "${LEAD_THREAD_ID:-}"
    }
  },
  "created_at": "$NOW",
  "updated_at": "$NOW",
  "version": 1,
  "agents": {
    "developer-1": { "role": "developer", "capacity": 1, "active_issues": [], "saturated_cycles": 0 }
  },
  "issues": {}
}
STATE
  ok "state.json criado (1 developer, capacity=1)"
else
  ok "state.json já existe"
fi
echo ""

# =============================================================================
# 10. REGISTRY
# =============================================================================
echo "[ Registry ]"
REGISTRY="$HOME/.openclaw/workspace/registry.json"
[ -f "$REGISTRY" ] || echo '[]' > "$REGISTRY"
# Remover entrada anterior do mesmo projeto e adicionar atualizada
jq --arg p "$PROJECT" --arg repo "$REPO" --arg ch "$DISCORD_CHANNEL" \
   --arg g "$DISCORD_GUILD_ID" --arg cid "${CHANNEL_ID:-}" --arg ts "$NOW" \
   'map(select(.project != $p)) + [{
     project: $p, repo: $repo, channel: $ch,
     guild_id: $g, channel_id: $cid,
     created_at: $ts, status: "active"
   }]' "$REGISTRY" > /tmp/_reg.json && mv /tmp/_reg.json "$REGISTRY"
ok "Registry atualizado"
echo ""

# =============================================================================
# 11. MENSAGEM DE BOAS-VINDAS NO DISCORD
# =============================================================================
echo "[ Mensagem Discord ]"
if [ -n "$CHANNEL_ID" ]; then
  WELCOME_MSG="👋 Bem-vindo ao projeto **${PROJECT}**!\n📦 Repositório: https://github.com/${REPO}\n🤖 Squad: Product · Developer · Reviewer · Lead\n\n🧵 Threads dedicadas:\n• <#${DEV_THREAD_ID:-dev}> — implementação técnica\n• <#${REVIEW_THREAD_ID:-review}> — revisão de código\n• <#${LEAD_THREAD_ID:-lead}> — gestão e relatórios\n\n📋 Board: ${BOARD_NAME}\n⏱️ Standup: 23:00 UTC na thread lead\n\nPara demandas, escreva aqui. O Product responde em tempo real 👀"

  openclaw message send \
    --channel discord \
    --target "channel:${CHANNEL_ID}" \
    --message "$WELCOME_MSG" 2>/dev/null \
    && ok "Mensagem de boas-vindas enviada" \
    || warn "Mensagem de boas-vindas não enviada (openclaw gateway precisa estar rodando)"
else
  warn "CHANNEL_ID não disponível — mensagem de boas-vindas não enviada"
fi
echo ""

# =============================================================================
# 12. HEALTH CHECK PÓS-PROVISIONAMENTO
# =============================================================================
echo "[ Health Check ]"
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPTS_DIR/health_check.sh" "$PROJECT" 2>/dev/null \
  && ok "Health check: PASSOU" \
  || warn "Health check encontrou avisos — verifique acima"
echo ""

echo "✅ Provisionamento completo: $PROJECT"
echo ""
echo "IDs Discord registrados:"
echo "  Canal principal:  ${CHANNEL_ID:-<não configurado>}"
echo "  Thread dev:       ${DEV_THREAD_ID:-<não configurado>}"
echo "  Thread review:    ${REVIEW_THREAD_ID:-<não configurado>}"
echo "  Thread lead:      ${LEAD_THREAD_ID:-<não configurado>}"
echo ""
echo "Próximos passos se algum ID ficou vazio:"
echo "  1. Crie o canal/thread manualmente no Discord"
echo "  2. Execute: rebind_threads.sh $PROJECT $DISCORD_CHANNEL $DISCORD_GUILD_ID"
