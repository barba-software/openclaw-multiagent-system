#!/usr/bin/env bash
# =============================================================================
# scale_developer.sh — Adiciona um novo developer ao projeto
# =============================================================================
# Uso: scale_developer.sh <project> <repo>
#
# Executado pelo Lead quando capacity está saturada por >2 ciclos consecutivos.
# Sempre aguarda confirmação explícita do usuário antes de agir.
#
# O que faz:
#   1. Calcula o próximo número de developer disponível
#   2. Adiciona developer-N ao state.json com capacity=1
#   3. Cria o cron de heartbeat do novo developer
#   4. Registra no audit.log
# =============================================================================

set -euo pipefail

PROJECT="${1:-}"
REPO="${2:-}"

if [ -z "$PROJECT" ] || [ -z "$REPO" ]; then
  echo "Uso: scale_developer.sh <project> <repo>"
  echo ""
  echo "Exemplo: scale_developer.sh meu-projeto owner/repo"
  exit 1
fi

BASE="$HOME/.openclaw/workspace/projects/$PROJECT"
STATE_FILE="$BASE/state.json"
AUDIT_LOG="$BASE/audit.log"
LOCK_FILE="$BASE/state.lock"
STATE_TMP="$BASE/state.tmp.json"
NOW=$(date -Iseconds)

if [ ! -f "$STATE_FILE" ]; then
  echo "❌ state.json não encontrado: $STATE_FILE"
  echo "   Execute primeiro: provision.sh $PROJECT $REPO ..."
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "❌ jq não encontrado"
  exit 1
fi

# ── Calcular próximo número de developer ─────────────────────────────────────
CURRENT_COUNT=$(jq '[.agents | to_entries[] | select(.value.role == "developer")] | length' "$STATE_FILE")
NEXT_NUM=$((CURRENT_COUNT + 1))
NEW_AGENT="developer-${NEXT_NUM}"

echo "================================================="
echo "  OpenClaw — Scale Developer"
echo "================================================="
echo ""
echo "Projeto:      $PROJECT"
echo "Developers:   $CURRENT_COUNT → $((CURRENT_COUNT + 1))"
echo "Novo agente:  $NEW_AGENT (capacity=1)"
echo ""

# ── Verificar se já existe ────────────────────────────────────────────────────
if jq -e --arg a "$NEW_AGENT" '.agents[$a]' "$STATE_FILE" &>/dev/null; then
  echo "⚠ Agente '$NEW_AGENT' já existe no state.json"
  echo "  Verifique se o escalonamento já foi feito."
  exit 1
fi

# ── Lock + escrita atômica ────────────────────────────────────────────────────
exec 9>"$LOCK_FILE"
if ! flock -w 5 9; then
  echo "⚠ State em uso. Tente novamente."
  exit 2
fi

# Backup antes de modificar
cp "$STATE_FILE" "${STATE_FILE}.bak"

NEW_STATE=$(jq \
  --arg a "$NEW_AGENT" --arg ts "$NOW" \
  '.agents[$a] = { "role": "developer", "capacity": 1, "active_issues": [], "added_at": $ts }' \
  "$STATE_FILE")

echo "$NEW_STATE" > "$STATE_TMP"
if ! jq -e . "$STATE_TMP" &>/dev/null; then
  echo "❌ JSON gerado inválido — operação abortada"
  rm -f "$STATE_TMP"
  exit 1
fi
mv "$STATE_TMP" "$STATE_FILE"

# Bump version
V=$(jq '.version // 0' "$STATE_FILE")
jq --argjson v "$((V+1))" --arg ts "$NOW" '.version = $v | .updated_at = $ts' \
  "$STATE_FILE" > "$STATE_TMP" && mv "$STATE_TMP" "$STATE_FILE"

# Audit
printf '[%s] project=%s event=scale_developer action=add_developer agent=%s status=OK\n' \
  "$NOW" "$PROJECT" "$NEW_AGENT" >> "$AUDIT_LOG"

echo "✔ $NEW_AGENT adicionado ao state.json (capacity=1)"

# ── Criar cron de heartbeat e agente openclaw ────────────────────────────────
CRON_NAME="${PROJECT}-${NEW_AGENT}-hb"
AGENT_OPENCLAW="${PROJECT}-developer"   # rota para o agente developer do projeto
WS="$HOME/.openclaw/workspace/projects/$PROJECT/agents/developer"

echo ""
echo "Criando cron e agente para $NEW_AGENT..."

if command -v openclaw &>/dev/null; then
  openclaw cron delete "$CRON_NAME" 2>/dev/null || true
  openclaw cron add \
    --name "$CRON_NAME" \
    --agent "$AGENT_OPENCLAW" \
    --every 15m \
    --session isolated \
    --message "Heartbeat $NEW_AGENT: leia AGENTS.md, verifique sua fila no state.json como $NEW_AGENT, use EXECUTE_ISSUE." \
    --no-deliver 2>/dev/null \
    && echo "✔ Cron criado: $CRON_NAME" \
    || echo "⚠ Falha ao criar cron — crie manualmente"

  # Nota: no OpenClaw um único agente openclaw (${PROJECT}-developer) processa
  # múltiplos developers internos do state.json. O NEW_AGENT é apenas o ID
  # interno de capacidade — o agente openclaw é o mesmo (shared session routing).
  echo ""
  echo "ℹ Arquitetura de scaling:"
  echo "  O agente openclaw '${PROJECT}-developer' é único e processa"
  echo "  as issues atribuídas ao $NEW_AGENT via state.json."
  echo "  Para um agente openclaw dedicado, provisione um novo agente manualmente:"
  echo "  openclaw agents add ${PROJECT}-$NEW_AGENT --workspace $WS"
else
  echo "⚠ openclaw CLI não disponível — crie o cron manualmente:"
  echo "  openclaw cron add --name $CRON_NAME --agent $AGENT_OPENCLAW --every 15m --session isolated --message 'Heartbeat $NEW_AGENT' --no-deliver"
fi

echo ""
echo "================================================="
echo "✅ Escalonamento concluído"
echo ""
echo "Resumo:"
jq '.agents | to_entries | map(select(.value.role == "developer")) | map({agent: .key, capacity: .value.capacity, active: (.value.active_issues | length)})' "$STATE_FILE"
echo ""
echo "O próximo auto_assign distribuirá issues entre os developers disponíveis."
echo "================================================="
