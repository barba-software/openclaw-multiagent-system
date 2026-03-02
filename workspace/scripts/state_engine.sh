#!/usr/bin/env bash
# =============================================================================
# state_engine.sh — Motor de Estado Central do OpenClaw
# =============================================================================
# Uso: state_engine.sh <project> <repo> <issue> <event> [metadata]
#
# Eventos suportados:
#   issue_created   → inbox        (product recebe)
#   auto_assign     → in_progress  (developer atribuído por capacidade)
#   pr_created      → review       (reviewer assume)
#   pr_approved     → approved     (aguardando merge)
#   blocked         → blocked      (bloqueio reportado)
#   unblocked       → in_progress  (bloqueio resolvido)
#   pr_merged       → done         (concluído, capacidade liberada)
#   reopened        → inbox        (issue reaberta)
#
# Exit codes:
#   0 = sucesso
#   1 = erro de argumento / estado inválido / evento desconhecido
#   2 = lock em uso (concorrência)
#   3 = nenhum developer disponível
# =============================================================================

set -euo pipefail

# ── Autenticação GitHub ────────────────────────────────────────────────────────
if [ -n "${GH_TOKEN:-}" ]; then
  export GH_TOKEN
elif [ -n "${GITHUB_TOKEN:-}" ]; then
  export GH_TOKEN="$GITHUB_TOKEN"
elif [ -f "$HOME/.config/gh/hosts.yml" ]; then
  _token=$(grep -A2 "github.com" "$HOME/.config/gh/hosts.yml" \
    | grep "oauth_token" | awk '{print $2}' | head -1 || true)
  [ -n "$_token" ] && export GH_TOKEN="$_token"
fi
[ -z "${GH_TOKEN:-}" ] && echo "❌ GH_TOKEN não definido — export GH_TOKEN=seu_token" && exit 1


# ── Argumentos ────────────────────────────────────────────────────────────────
PROJECT="${1:-}"
REPO="${2:-}"
ISSUE="${3:-}"
EVENT="${4:-}"
METADATA="${5:-}"

if [ -z "$PROJECT" ] || [ -z "$REPO" ] || [ -z "$ISSUE" ] || [ -z "$EVENT" ]; then
  echo "Uso: state_engine.sh <project> <repo> <issue> <event> [metadata]"
  echo ""
  echo "Eventos: issue_created | auto_assign | pr_created | pr_approved |"
  echo "         blocked | unblocked | pr_merged | reopened"
  exit 1
fi

# ── Paths ─────────────────────────────────────────────────────────────────────
BASE="$HOME/.openclaw/workspace/projects/$PROJECT"
STATE_FILE="$BASE/state.json"
STATE_TMP="$BASE/state.tmp.json"
LOCK_FILE="$BASE/state.lock"
AUDIT_LOG="$BASE/audit.log"
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Dependências ──────────────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "❌ jq não encontrado. Instale: apt install jq"
  exit 1
fi

if [ ! -d "$BASE" ]; then
  echo "❌ Projeto '$PROJECT' não encontrado em $BASE"
  echo "   Execute: provision.sh $PROJECT $REPO <discord_channel_id>"
  exit 1
fi

# ── Lock ──────────────────────────────────────────────────────────────────────
exec 9>"$LOCK_FILE"
if ! flock -w 5 9; then
  echo "⚠ State em uso. Aguardou 5s sem conseguir o lock."
  exit 2
fi

# ── Timestamp ─────────────────────────────────────────────────────────────────
NOW=$(date -Iseconds)

# ── Inicializar state.json ────────────────────────────────────────────────────
if [ ! -f "$STATE_FILE" ]; then
  echo "📄 Criando state.json para projeto '$PROJECT'..."
  cat > "$STATE_FILE" <<STATE
{
  "project": "$PROJECT",
  "repo": "$REPO",
  "created_at": "$NOW",
  "updated_at": "$NOW",
  "version": 1,
  "agents": {
    "developer-1": { "role": "developer", "capacity": 2, "active_issues": [] },
    "developer-2": { "role": "developer", "capacity": 2, "active_issues": [] }
  },
  "issues": {}
}
STATE
fi

# ── Validar schema ────────────────────────────────────────────────────────────
validate_state() {
  local err=0

  if ! jq -e 'type == "object"' "$STATE_FILE" &>/dev/null; then
    echo "❌ state.json: JSON inválido ou não é objeto"
    return 1
  fi

  for field in project repo agents issues; do
    if ! jq -e "has(\"$field\")" "$STATE_FILE" &>/dev/null; then
      echo "❌ state.json: campo obrigatório '$field' ausente"
      err=$((err+1))
    fi
  done

  if ! jq -e '.agents | type == "object"' "$STATE_FILE" &>/dev/null; then
    echo "❌ state.json: .agents deve ser um objeto"
    err=$((err+1))
  fi

  # Validar estrutura de cada agente
  while IFS= read -r ag; do
    for f in role capacity active_issues; do
      if ! jq -e ".agents[\"$ag\"] | has(\"$f\")" "$STATE_FILE" &>/dev/null; then
        echo "❌ state.json: agente '$ag' sem campo '$f'"
        err=$((err+1))
      fi
    done
    if ! jq -e ".agents[\"$ag\"].active_issues | type == \"array\"" "$STATE_FILE" &>/dev/null; then
      echo "❌ state.json: agente '$ag'.active_issues não é array"
      err=$((err+1))
    fi
  done < <(jq -r '.agents | keys[]' "$STATE_FILE" 2>/dev/null || true)

  return $err
}

if ! validate_state; then
  echo ""
  echo "⚠ state.json corrompido. Verifique $STATE_FILE"
  echo "  Backup: ${STATE_FILE}.bak"
  exit 1
fi

# ── Audit log ─────────────────────────────────────────────────────────────────
audit() {
  local action="$1"
  local detail="${2:-}"
  local status="${3:-OK}"
  printf '[%s] project=%s issue=%s event=%s action=%s status=%s %s\n' \
    "$NOW" "$PROJECT" "$ISSUE" "$EVENT" "$action" "$status" "$detail" \
    >> "$AUDIT_LOG"
}

# ── Backup / Rollback ─────────────────────────────────────────────────────────
backup_state() {
  cp "$STATE_FILE" "${STATE_FILE}.bak"
}

rollback_state() {
  if [ -f "${STATE_FILE}.bak" ]; then
    cp "${STATE_FILE}.bak" "$STATE_FILE"
    audit "rollback" "state restaurado do backup" "WARN"
    echo "⚠ Estado restaurado do backup (rollback)"
  else
    audit "rollback_failed" "backup nao encontrado" "ERROR"
    echo "❌ Rollback falhou: backup não encontrado"
  fi
}

# ── Escrita segura do state ───────────────────────────────────────────────────
write_state() {
  echo "$1" > "$STATE_TMP"
  if ! jq -e . "$STATE_TMP" &>/dev/null; then
    echo "❌ JSON gerado inválido — mutação abortada"
    rm -f "$STATE_TMP"
    return 1
  fi
  mv "$STATE_TMP" "$STATE_FILE"
}

bump_version() {
  local v
  v=$(jq '.version // 0' "$STATE_FILE")
  local new_state
  new_state=$(jq --argjson v "$((v+1))" --arg ts "$NOW" \
    '.version = $v | .updated_at = $ts' "$STATE_FILE")
  write_state "$new_state"
}

# ── Helpers de leitura ────────────────────────────────────────────────────────
get_issue_agent() {
  jq -r --arg i "$ISSUE" '.issues[$i].assigned_agent // empty' "$STATE_FILE"
}

get_issue_status() {
  jq -r --arg i "$ISSUE" '.issues[$i].status // empty' "$STATE_FILE"
}

# ── Atualizar status de issue ─────────────────────────────────────────────────
update_issue() {
  local status="$1"
  local agent="$2"
  local new_state
  new_state=$(jq \
    --arg i "$ISSUE" --arg s "$status" --arg a "$agent" --arg ts "$NOW" --arg m "$METADATA" \
    '.issues[$i] |= (. // {} | .status=$s | .assigned_agent=$a | .updated_at=$ts |
     if $m != "" then .last_metadata=$m else . end)' \
    "$STATE_FILE")
  write_state "$new_state"
  bump_version
  audit "update_issue" "status=$status agent=$agent"
}

# ── Atribuição por capacidade ─────────────────────────────────────────────────
assign_by_capacity() {
  local dev
  dev=$(jq -r '
    .agents | to_entries
    | map(select(.value.role == "developer"))
    | map(select((.value.active_issues | length) < .value.capacity))
    | sort_by(.value.active_issues | length)
    | .[0].key // empty
  ' "$STATE_FILE")

  if [ -z "$dev" ]; then
    echo "❌ Nenhum developer disponível (todos no limite de capacidade)"
    audit "assign_by_capacity" "no_developer_available" "ERROR"
    exit 3
  fi

  local new_state
  new_state=$(jq \
    --arg i "$ISSUE" --arg d "$dev" --arg ts "$NOW" \
    '.issues[$i] = { status: "in_progress", assigned_agent: $d, created_at: $ts, updated_at: $ts } |
     .agents[$d].active_issues += [$i]' \
    "$STATE_FILE")
  write_state "$new_state"
  bump_version
  audit "assign_by_capacity" "developer=$dev"
  echo "✔ Issue #$ISSUE atribuída para $dev (state)"
  sync_label "$ISSUE" "in_progress"

  # Acordar o agente developer via openclaw send
  local agent_id="$PROJECT-$dev"
  local msg="HEARTBEAT: Issue #$ISSUE atribuída. Verifique sua fila com EXECUTE_ISSUE e inicie a implementação."
  openclaw send --agent "$agent_id" --message "$msg" &>/dev/null \
    && audit "openclaw_send" "agent=$agent_id" \
    && echo "✔ Agente $agent_id notificado" \
    || echo "⚠ Não foi possível notificar $agent_id via openclaw (continuando)"
}

# ── FIX: release_capacity — estava indefinida, causa de crash no pr_merged ────
release_capacity() {
  local agent
  agent=$(get_issue_agent)

  if [ -z "$agent" ]; then
    echo "⚠ Issue #$ISSUE sem agente atribuído — nada a liberar"
    audit "release_capacity" "no_agent_found" "WARN"
    return 0
  fi

  local role
  role=$(jq -r --arg a "$agent" '.agents[$a].role // empty' "$STATE_FILE")

  if [ "$role" != "developer" ]; then
    echo "⚠ Agente '$agent' (role=$role) — capacidade não é gerenciada"
    audit "release_capacity" "not_developer agent=$agent" "WARN"
    return 0
  fi

  local new_state
  new_state=$(jq \
    --arg i "$ISSUE" --arg a "$agent" \
    '.agents[$a].active_issues = (.agents[$a].active_issues | map(select(. != $i)))' \
    "$STATE_FILE")
  write_state "$new_state"
  audit "release_capacity" "developer=$agent issue_removed=$ISSUE"
  echo "✔ Capacidade liberada: $agent ← issue #$ISSUE removida"
}

# ── Obter PR da issue ────────────────────────────────────────────────────────
get_issue_pr() {
  jq -r --arg i "$ISSUE" '.issues[$i].pull_request // empty' "$STATE_FILE"
}

# ── Sync labels GitHub ────────────────────────────────────────────────────────
# Mapeia status interno → label no GitHub
sync_label() {
  local issue="$1" new_status="$2"
  local all_labels="inbox in_progress review blocked done"
  local status_label
  case "$new_status" in
    inbox)       status_label="inbox" ;;
    in_progress) status_label="in_progress" ;;
    review)      status_label="review" ;;
    blocked)     status_label="blocked" ;;
    done)        status_label="done" ;;
    approved)    status_label="review" ;;
    *)           return 0 ;;
  esac

  local pr
  pr=$(get_issue_pr)

  # Remover todas as labels de status e aplicar a nova na ISSUE
  for lbl in $all_labels; do
    gh issue edit "$issue" --repo "$REPO" --remove-label "$lbl" &>/dev/null || true
  done
  gh issue edit "$issue" --repo "$REPO" --add-label "$status_label" &>/dev/null \
    && audit "sync_label_issue" "issue=$issue label=$status_label" \
    || echo "  ⚠ label $status_label não aplicada na Issue #$issue"

  # Se houver um PR associado, aplicar a label no PR também
  if [ -n "$pr" ]; then
    for lbl in $all_labels; do
      gh pr edit "$pr" --repo "$REPO" --remove-label "$lbl" &>/dev/null || true
    done
    gh pr edit "$pr" --repo "$REPO" --add-label "$status_label" &>/dev/null \
      && audit "sync_label_pr" "pr=$pr label=$status_label" \
      || echo "  ⚠ label $status_label não aplicada no PR #$pr"
  fi
}

# ── automation.sh com retry + backoff ────────────────────────────────────────
call_automation() {
  local board_status="$1"
  local max=3 attempt=0 wait=5

  while [ $attempt -lt $max ]; do
    attempt=$((attempt+1))
    echo "  📡 board sync (tentativa $attempt/$max): $board_status"
    if "$SCRIPTS_DIR/automation.sh" "$PROJECT" "$REPO" "$ISSUE" "$board_status"; then
      audit "automation_sync" "board_status=$board_status attempt=$attempt"
      return 0
    fi
    if [ $attempt -lt $max ]; then
      echo "  ⏳ Tentativa $attempt falhou. Aguardando ${wait}s..."
      sleep $wait
      wait=$((wait * 2))
    fi
  done

  echo "⚠ Board GitHub não sincronizado após $max tentativas."
  echo "  Execute manualmente: $SCRIPTS_DIR/reconcile.sh $PROJECT $REPO"
  audit "automation_sync_failed" "board_status=$board_status retries=$max" "ERROR"
  return 0  # não propaga erro — estado interno foi preservado
}

# =============================================================================
# 🔄 Máquina de Estados
# =============================================================================

echo "▶ state-engine: project=$PROJECT issue=#$ISSUE event=$EVENT"
backup_state

case $EVENT in

  issue_created)
    update_issue "inbox" "product"
    sync_label "$ISSUE" "inbox"
    call_automation "Inbox"
    # Auto-assign imediato: não espera próximo heartbeat
    echo "  → auto_assign em seguida..."
    assign_by_capacity
    update_issue "in_progress" "$(get_issue_agent)"
    sync_label "$ISSUE" "in_progress"
    call_automation "In Progress"
    ;;

  auto_assign)
    assign_by_capacity
    call_automation "In Progress"
    ;;

  pr_created)
    # Salvar o developer atual antes de mudar para o reviewer
    local dev
    dev=$(get_issue_agent)
    
    # Capturar número do PR dos metadados ($5 recebido via state_engine.sh)
    local pr_number="${METADATA:-}"
    
    local state_with_pr
    state_with_pr=$(jq --arg i "$ISSUE" --arg d "$dev" --arg pr "$pr_number" \
      '.issues[$i].last_developer = $d | .issues[$i].pull_request = $pr' "$STATE_FILE")
    write_state "$state_with_pr"
    
    update_issue "review" "reviewer"
    sync_label "$ISSUE" "review"
    call_automation "Review"
    # Acordar reviewer
    local reviewer_agent="$PROJECT-reviewer"
    local msg="HEARTBEAT: PR aberta para Issue #$ISSUE. Verifique com REVIEW_PR e inicie a revisão."
    openclaw send --agent "$reviewer_agent" --message "$msg" &>/dev/null \
      && echo "✔ Reviewer $reviewer_agent notificado" \
      || echo "⚠ Não foi possível notificar reviewer (continuando)"
    ;;

  pr_approved)
    update_issue "approved" "reviewer"
    audit "pr_approved" "awaiting_merge"
    echo "✔ PR aprovado. Aguardando merge."
    ;;

  blocked)
    local current_agent
    current_agent=$(get_issue_agent)
    
    # Se o agente atual for o reviewer, devolvemos a bola para o developer original
    if [ "$current_agent" = "reviewer" ]; then
      local last_dev
      last_dev=$(jq -r --arg i "$ISSUE" '.issues[$i].last_developer // "lead"' "$STATE_FILE")
      update_issue "blocked" "$last_dev"
      
      # Notificar o developer sobre o feedback
      local dev_id="$PROJECT-$last_dev"
      local dev_msg="ALERTA: PR da Issue #$ISSUE precisa de ajustes. Veja os comentários no GitHub e use a skill EXECUTE_ISSUE."
      openclaw send --agent "$dev_id" --message "$dev_msg" &>/dev/null \
        || echo "  ⚠ Não foi possível notificar $dev_id"
    else
      update_issue "blocked" "lead"
    fi
    
    sync_label "$ISSUE" "blocked"
    call_automation "Blocked"
    
    # Notificar lead sempre por segurança
    local lead_agent="$PROJECT-lead"
    local msg="ALERTA: Issue #$ISSUE bloqueada. Motivo: ${METADATA:-não informado}."
    openclaw send --agent "$lead_agent" --message "$msg" &>/dev/null \
      && echo "✔ Lead $lead_agent notificado" \
      || echo "⚠ Não foi possível notificar lead"
    
    echo "🚨 Issue #$ISSUE bloqueada."
    ;;

  unblocked)
    # Se METADATA contiver nome de developer válido, reatribui; senão, auto_assign
    if [ -n "$METADATA" ] && jq -e --arg a "$METADATA" '.agents[$a].role == "developer"' "$STATE_FILE" &>/dev/null 2>&1; then
      update_issue "in_progress" "$METADATA"
      call_automation "In Progress"
      echo "✔ Issue #$ISSUE desbloqueada → reatribuída para $METADATA"
    else
      assign_by_capacity
      call_automation "In Progress"
      echo "✔ Issue #$ISSUE desbloqueada → developer reatribuído por capacidade"
    fi
    ;;

  pr_merged)
    release_capacity                   # FIX: agora implementada corretamente
    update_issue "done" "lead"
    sync_label "$ISSUE" "done"
    # Fechar issue no GitHub com retry
    local_closed=false
    for attempt in 1 2 3; do
      if gh issue close "$ISSUE" --repo "$REPO" &>/dev/null; then
        audit "gh_issue_close" "attempt=$attempt"
        local_closed=true
        break
      fi
      sleep $((attempt * 3))
    done
    if [ "$local_closed" = false ]; then
      echo "⚠ Não foi possível fechar a issue #$ISSUE no GitHub. Feche manualmente."
      audit "gh_issue_close_failed" "retries=3" "ERROR"
    fi
    call_automation "Done"
    ;;

  reopened)
    local prev_agent
    prev_agent=$(get_issue_agent)
    update_issue "inbox" "product"
    call_automation "Inbox"
    echo "♻ Issue #$ISSUE reaberta → inbox (era: ${prev_agent:-nenhum})"
    ;;

  *)
    echo "❌ Evento desconhecido: '$EVENT'"
    echo "   Válidos: issue_created | auto_assign | pr_created | pr_approved |"
    echo "            blocked | unblocked | pr_merged | reopened"
    audit "unknown_event" "event=$EVENT" "ERROR"
    exit 1
    ;;

esac

echo "✔ Concluído: Issue #$ISSUE → $EVENT"
audit "completed" "event=$EVENT"
