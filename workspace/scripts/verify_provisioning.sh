#!/usr/bin/env bash
# =============================================================================
# verify_provisioning.sh — Verifica integridade completa do provisionamento
# =============================================================================
# Uso: verify_provisioning.sh <project> <repo>
#
# Checa: workspace, agentes, crons, labels, board, bindings, repo, skills,
#        threads Discord, state.json, e consistência geral.
# Exit: 0=tudo ok, 1=avisos, 2=erros críticos
# =============================================================================

set -euo pipefail

PROJECT="${1:-}"
REPO="${2:-}"

if [ -z "$PROJECT" ] || [ -z "$REPO" ]; then
  echo "Uso: verify_provisioning.sh <project> <repo>"
  exit 1
fi

OWNER=$(echo "$REPO" | cut -d/ -f1)
BASE="$HOME/.openclaw/workspace/projects/$PROJECT"
AGENT_WS="$BASE/agents"
CONFIG="$HOME/.openclaw/openclaw.json"
SKILLS_BASE="$HOME/.openclaw/workspace/skills"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
EXIT_CODE=0
WARNINGS=0; ERRORS=0

ok()   { echo -e "  ${GREEN}✔${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; WARNINGS=$((WARNINGS+1)); [ $EXIT_CODE -lt 1 ] && EXIT_CODE=1; }
fail() { echo -e "  ${RED}❌${NC} $1"; ERRORS=$((ERRORS+1)); EXIT_CODE=2; }

echo "======================================================="
echo "  Verify Provisioning — $PROJECT"
echo "  $(date)"
echo "======================================================="

# ── 1. Estrutura de diretórios ────────────────────────────────────────────────
echo ""
echo "[ Estrutura ]"
for dir in "memory/product" "memory/developer" "memory/reviewer" "memory/lead" "agents"; do
  [ -d "$BASE/$dir" ] && ok "$dir" || fail "Diretório ausente: $BASE/$dir"
done

# ── 2. Workspaces dos agentes ─────────────────────────────────────────────────
echo ""
echo "[ Workspaces de agentes ]"
for role in product developer reviewer lead; do
  ws="$AGENT_WS/$role"
  [ -d "$ws" ] || { fail "Workspace ausente: $ws"; continue; }
  for doc in SOUL.md AGENTS.md HEARTBEAT.md IDENTITY.md WORKING.md; do
    [ -f "$ws/$doc" ] && ok "$role/$doc" || fail "$role/$doc ausente"
  done
  # Verificar se templates foram substituídos (não devem conter {{PROJECT}})
  if grep -q "{{PROJECT}}" "$ws/SOUL.md" 2>/dev/null; then
    fail "$role/SOUL.md: variáveis {{PROJECT}} não foram substituídas"
  fi
done

# ── 3. Skills globais ─────────────────────────────────────────────────────────
echo ""
echo "[ Skills globais em $SKILLS_BASE ]"
REQUIRED_SKILLS=(
  "create_product_issue"
  "execute_issue"
  "review_pr"
  "daily_standup"
  "reconcile_state"
  "block_detection"
  "create_openclaw_squad"
  "start_project"
  "auto_label"
  "risk_analysis"
  "reprioritize_backlog"
  "cross_project_report"
  "sprint_mode"
  "pause_project"
  "archive_project"
  "performance_audit"
  "scale_developer"
  "policies/PERMISSIONS.md"
  "policies/EXECUTION_RULES.md"
)
for skill in "${REQUIRED_SKILLS[@]}"; do
  skill_path="$SKILLS_BASE/$skill"
  [ -d "$skill_path" ] || [ -f "$skill_path" ] \
    && ok "Skill: $skill" \
    || fail "Skill ausente: $skill — agentes não conseguirão usá-la"
done

# ── 4. Agentes openclaw ───────────────────────────────────────────────────────
echo ""
echo "[ Agentes openclaw ]"
for role in product developer reviewer lead; do
  agent="${PROJECT}-$role"
  openclaw agents list 2>/dev/null | grep -q "$agent" \
    && ok "Agente: $agent" \
    || fail "Agente não encontrado: $agent"
done

# ── 5. Crons ─────────────────────────────────────────────────────────────────
echo ""
echo "[ Crons ]"
REQUIRED_CRONS=(
  "${PROJECT}-product-hb"
  "${PROJECT}-dev-hb"
  "${PROJECT}-review-hb"
  "${PROJECT}-lead-standup"
  "${PROJECT}-lead-reconcile"
  "${PROJECT}-lead-hb"
)
for cron in "${REQUIRED_CRONS[@]}"; do
  openclaw cron list 2>/dev/null | grep -q "$cron" \
    && ok "Cron: $cron" \
    || fail "Cron não encontrado: $cron"
done

# ── 6. Labels GitHub ──────────────────────────────────────────────────────────
echo ""
echo "[ Labels GitHub ]"
EXISTING_LABELS=$(gh label list --repo "$REPO" --json name --jq '.[].name' 2>/dev/null || true)
for lbl in inbox in_progress review blocked done \
           "agent:product" "agent:developer" "agent:reviewer" \
           "p0:critica" "p1:alta" "p2:normal" "p3:baixa"; do
  echo "$EXISTING_LABELS" | grep -qx "$lbl" \
    && ok "Label: $lbl" \
    || warn "Label ausente: $lbl — execute provision.sh novamente"
done

# ── 7. Board GitHub ───────────────────────────────────────────────────────────
echo ""
echo "[ Board GitHub ]"
BOARD_NAME="$PROJECT Board"
OWNER_NODE_ID=$(gh api "orgs/$OWNER" --jq .node_id 2>/dev/null \
  || gh api "users/$OWNER" --jq .node_id 2>/dev/null || true)

if [ -n "$OWNER_NODE_ID" ]; then
  BOARD_JSON=$(gh api graphql -f query="
    query { node(id: \"$OWNER_NODE_ID\") {
      ... on User         { projectsV2(first:20) { nodes { id title closed fields(first:20) {
        nodes { ... on ProjectV2SingleSelectField { name options { name } } }
      } } } }
      ... on Organization { projectsV2(first:20) { nodes { id title closed fields(first:20) {
        nodes { ... on ProjectV2SingleSelectField { name options { name } } }
      } } } }
    } }
  " 2>/dev/null || true)

  BOARD_EXISTS=$(echo "$BOARD_JSON" | jq -r ".data.node.projectsV2.nodes[] | select(.title == \"$BOARD_NAME\" and .closed == false) | .title" 2>/dev/null | head -1 || true)
  if [ -n "$BOARD_EXISTS" ]; then
    ok "Board: $BOARD_NAME"
    # Verificar colunas
    for col in "Inbox" "In Progress" "Review" "Blocked" "Done"; do
      echo "$BOARD_JSON" | grep -q "\"name\":\"$col\"" \
        && ok "Coluna: $col" \
        || fail "Coluna ausente no board: $col — automation.sh vai falhar"
    done
  else
    fail "Board '$BOARD_NAME' não encontrado — issues não serão adicionadas ao board"
  fi
else
  warn "Não foi possível verificar board (sem acesso ao owner $OWNER)"
fi

# ── 8. Discord IDs e bindings ─────────────────────────────────────────────────
echo ""
echo "[ Discord ]"
if [ -f "$BASE/discord_ids.json" ]; then
  ok "discord_ids.json presente"
  CHANNEL_ID=$(jq -r '.channel_id // empty' "$BASE/discord_ids.json")
  DEV_ID=$(jq -r '.dev_thread_id // empty' "$BASE/discord_ids.json")
  REVIEW_ID=$(jq -r '.review_thread_id // empty' "$BASE/discord_ids.json")
  LEAD_ID=$(jq -r '.lead_thread_id // empty' "$BASE/discord_ids.json")
  [ -n "$CHANNEL_ID" ]  && ok "CHANNEL_ID: $CHANNEL_ID"  || warn "CHANNEL_ID ausente — product agent não está vinculado ao canal"
  [ -n "$DEV_ID" ]      && ok "DEV_THREAD_ID: $DEV_ID"   || warn "DEV_THREAD_ID ausente — developer não está vinculado à thread"
  [ -n "$REVIEW_ID" ]   && ok "REVIEW_THREAD_ID: $REVIEW_ID" || warn "REVIEW_THREAD_ID ausente"
  [ -n "$LEAD_ID" ]     && ok "LEAD_THREAD_ID: $LEAD_ID"  || warn "LEAD_THREAD_ID ausente"

  if [ -f "$CONFIG" ]; then
    for role in product developer reviewer lead; do
      agent="${PROJECT}-$role"
      jq -e ".bindings[] | select(.agentId == \"$agent\")" "$CONFIG" &>/dev/null \
        && ok "Binding Discord: $agent" \
        || warn "Binding ausente: $agent — agente não responde no Discord"
    done
  fi
else
  warn "discord_ids.json ausente — execute provision.sh com os IDs do Discord"
fi

# ── 9. Repo clonado ───────────────────────────────────────────────────────────
echo ""
echo "[ Repo ]"
[ -d "$BASE/repo/.git" ] \
  && ok "Repo clonado em $BASE/repo" \
  || warn "Repo não clonado — developer não conseguirá commitar. Execute: git clone https://github.com/$REPO.git $BASE/repo"

# ── 10. Scripts executáveis ───────────────────────────────────────────────────
echo ""
echo "[ Scripts ]"
SCRIPTS_DIR="$HOME/.openclaw/workspace/scripts"
for script in provision.sh state_engine.sh automation.sh health_check.sh \
              reconcile.sh scale_developer.sh inbox-dispatch.sh \
              create_and_dispatch.sh sync-labels.sh rebind_threads.sh \
              verify_provisioning.sh; do
  [ -f "$SCRIPTS_DIR/$script" ] \
    && ok "Script: $script" \
    || fail "Script ausente: $SCRIPTS_DIR/$script"
done

# ── 11. Consistência state.json ───────────────────────────────────────────────
echo ""
echo "[ State.json ]"
STATE="$BASE/state.json"
if [ -f "$STATE" ]; then
  jq -e . "$STATE" &>/dev/null && ok "state.json é JSON válido" || fail "state.json inválido"
  jq -e '.agents["developer-1"].capacity == 1' "$STATE" &>/dev/null \
    && ok "developer-1 capacity=1 (correto)" \
    || warn "developer-1 sem capacity=1 — verifique state.json"
  ACTIVE=$(jq '[.agents[] | select(.role=="developer") | .active_issues | length] | add // 0' "$STATE")
  CAP=$(jq '[.agents[] | select(.role=="developer") | .capacity] | add // 0' "$STATE")
  [ "$ACTIVE" -le "$CAP" ] && ok "Capacidade developers: $ACTIVE/$CAP" \
    || fail "Desenvolvedores acima da capacidade: $ACTIVE/$CAP"
else
  warn "state.json ainda não criado (normal se nenhuma issue foi criada)"
fi

# ── Resumo ────────────────────────────────────────────────────────────────────
echo ""
echo "======================================================="
echo "  Resultado: $WARNINGS avisos | $ERRORS erros críticos"
if [ $EXIT_CODE -eq 0 ]; then
  echo -e "  ${GREEN}✅ PROVISIONAMENTO ÍNTEGRO${NC}"
elif [ $EXIT_CODE -eq 1 ]; then
  echo -e "  ${YELLOW}⚠  AVISOS — sistema operacional mas com itens pendentes${NC}"
else
  echo -e "  ${RED}❌ ERROS CRÍTICOS — provisione novamente${NC}"
  echo "  Execute: bash provision.sh $PROJECT $REPO ..."
fi
echo "======================================================="
exit $EXIT_CODE
