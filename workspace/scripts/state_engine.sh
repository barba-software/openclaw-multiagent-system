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

# ── Discord Context ───────────────────────────────────────────────────────────
if [ -f "$STATE_FILE" ]; then
  _guild=$(jq -r '.discord_guild_id // empty' "$STATE_FILE")
  [ -n "$_guild" ] && export DISCORD_GUILD_ID="$_guild"
fi

# ── Inicializar state.json ────────────────────────────────────────────────────
# FC-01 CORRIGIDO: sempre começa com 1 developer, capacity=1
# Para escalar: bash scale_developer.sh <project> <repo>
if [ ! -f "$STATE_FILE" ]; then
  echo "📄 Criando state.json para '$PROJECT' (1 developer, capacity=1)..."
  cat > "$STATE_FILE" <<STATE
{
  "project": "$PROJECT",
  "repo": "$REPO",
  "discord_guild_id": "${DISCORD_GUILD_ID:-}",
  "created_at": "$NOW",
  "updated_at": "$NOW",
  "version": 1,
  "agents": {
    "developer-1": { "role": "developer", "capacity": 1, "active_issues": [] }
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
  local v new_state
  v=$(jq '.version // 0' "$STATE_FILE")
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
  local status="$1" agent="$2" new_state
  new_state=$(jq \
    --arg i "$ISSUE" --arg s "$status" --arg a "$agent" --arg ts "$NOW" --arg m "$METADATA" \
    '.issues[$i] |= (. // {} | .status=$s | .assigned_agent=$a | .updated_at=$ts |
     if $m != "" then .last_metadata=$m else . end)' \
    "$STATE_FILE")
  write_state "$new_state"
  bump_version
  audit "update_issue" "status=$status agent=$agent"
}

# ── Mapeia chave do state.json → ID do agente OpenClaw ───────────────────────
# developer-1 → {PROJECT}-developer  (agente inicial criado pelo provision.sh)
# developer-2, developer-N → {PROJECT}-developer-2  (agentes escalados via scale_developer.sh)
# outros (reviewer, lead, product) → {PROJECT}-{key}
map_agent_id() {
  local key="$1"
  if [ "$key" = "developer-1" ]; then
    echo "$PROJECT-developer"
  else
    echo "$PROJECT-$key"
  fi
}

# ── Atribuição por capacidade ─────────────────────────────────────────────────
assign_by_capacity() {
  local dev new_state agent_id msg
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
    notify_lead_saturation
    exit 3
  fi

  new_state=$(jq \
    --arg i "$ISSUE" --arg d "$dev" --arg ts "$NOW" \
    '.issues[$i] = { status: "in_progress", assigned_agent: $d, created_at: $ts, updated_at: $ts, created_via: "state_engine" } |
     .agents[$d].active_issues += [$i]' \
    "$STATE_FILE")
  write_state "$new_state"
  bump_version
  audit "assign_by_capacity" "developer=$dev"
  echo "✔ Issue #$ISSUE atribuída para $dev"
  sync_label "$ISSUE" "in_progress"

  agent_id=$(map_agent_id "$dev")
  msg="🔔 NOVA TAREFA: Issue #$ISSUE atribuída a você. Use a skill EXECUTE_ISSUE para iniciar. Anuncie imediatamente na thread ${PROJECT}-dev antes de começar."
  openclaw send --agent "$agent_id" --message "$msg" &>/dev/null \
    && audit "openclaw_send" "agent=$agent_id" \
    && echo "✔ $agent_id notificado" \
    || echo "⚠ Não foi possível notificar $agent_id (continuando)"
}

# ── Notificar Lead sobre saturação ───────────────────────────────────────────
notify_lead_saturation() {
  local total_capacity active_count lead_agent sat_msg new_cycles
  total_capacity=$(jq '[.agents[] | select(.role=="developer") | .capacity] | add // 0' "$STATE_FILE")
  active_count=$(jq '[.agents[] | select(.role=="developer") | .active_issues | length] | add // 0' "$STATE_FILE")

  # Incrementar contador de ciclos saturados (usado pelo Lead para decidir SCALE_DEVELOPER)
  new_cycles=$(jq '
    [.agents | to_entries[] | select(.value.role=="developer") | .value.saturated_cycles // 0] | max // 0 | . + 1
  ' "$STATE_FILE")
  local tmp_sc
  tmp_sc=$(mktemp)
  jq --argjson c "$new_cycles" '
    .agents |= with_entries(
      if .value.role == "developer" then .value.saturated_cycles = $c else . end
    )
  ' "$STATE_FILE" > "$tmp_sc" && mv "$tmp_sc" "$STATE_FILE"
  audit "saturation_cycle" "cycles=$new_cycles total=${active_count}/${total_capacity}"

  lead_agent="$PROJECT-lead"
  sat_msg="⚠️ CAPACIDADE SATURADA: Issue #$ISSUE não pôde ser atribuída. Developers no limite (${active_count}/${total_capacity}). Ciclos saturados: ${new_cycles}. $([ "$new_cycles" -ge 2 ] && echo 'AÇÃO NECESSÁRIA — execute: bash ~/.openclaw/workspace/scripts/scale_developer.sh '"$PROJECT $REPO" || echo 'Aguardando próximo ciclo.')"
  openclaw send --agent "$lead_agent" --message "$sat_msg" &>/dev/null \
    && echo "✔ Lead notificado sobre saturação (ciclo $new_cycles)" \
    || echo "⚠ Não foi possível notificar lead sobre saturação"
}

# ── release_capacity ──────────────────────────────────────────────────────────
release_capacity() {
  local agent role new_state
  agent=$(get_issue_agent)

  if [ -z "$agent" ]; then
    echo "⚠ Issue #$ISSUE sem agente atribuído — nada a liberar"
    audit "release_capacity" "no_agent_found" "WARN"
    return 0
  fi

  role=$(jq -r --arg a "$agent" '.agents[$a].role // empty' "$STATE_FILE")

  if [ "$role" != "developer" ]; then
    echo "⚠ Agente '$agent' (role=$role) — capacidade não gerenciada"
    audit "release_capacity" "not_developer agent=$agent" "WARN"
    return 0
  fi

  new_state=$(jq \
    --arg i "$ISSUE" --arg a "$agent" \
    '.agents[$a].active_issues = (.agents[$a].active_issues | map(select(. != $i)))' \
    "$STATE_FILE")
  write_state "$new_state"
  audit "release_capacity" "developer=$agent issue_removed=$ISSUE"
  echo "✔ Capacidade liberada: $agent ← issue #$ISSUE removida"
}

# ── Obter PR da issue ─────────────────────────────────────────────────────────
get_issue_pr() {
  jq -r --arg i "$ISSUE" '.issues[$i].pull_request // empty' "$STATE_FILE"
}

# ── Sync labels GitHub ────────────────────────────────────────────────────────
sync_label() {
  local issue="$1" new_status="$2"
  local all_status_labels="inbox in_progress review blocked done"
  local all_agent_labels="agent:product agent:developer agent:reviewer"
  local status_label agent_label=""

  case "$new_status" in
    inbox)       status_label="inbox";       agent_label="agent:product"   ;;
    in_progress) status_label="in_progress"; agent_label="agent:developer" ;;
    review)      status_label="review";      agent_label="agent:reviewer"  ;;
    approved)    status_label="review";      agent_label="agent:reviewer"  ;;
    blocked)     status_label="blocked" ;;
    done)        status_label="done"    ;;
    *)           return 0              ;;
  esac

  local pr
  pr=$(get_issue_pr)

  for lbl in $all_status_labels; do
    gh issue edit "$issue" --repo "$REPO" --remove-label "$lbl" &>/dev/null || true
  done
  if [ -n "$agent_label" ]; then
    for lbl in $all_agent_labels; do
      gh issue edit "$issue" --repo "$REPO" --remove-label "$lbl" &>/dev/null || true
    done
    gh issue edit "$issue" --repo "$REPO" --add-label "$agent_label" &>/dev/null || true
  fi
  gh issue edit "$issue" --repo "$REPO" --add-label "$status_label" &>/dev/null \
    && audit "sync_label_issue" "issue=$issue status=$status_label agent=$agent_label" \
    || echo "  ⚠ falha ao sincronizar labels na Issue #$issue"

  if [ -n "$pr" ]; then
    for lbl in $all_status_labels; do
      gh pr edit "$pr" --repo "$REPO" --remove-label "$lbl" &>/dev/null || true
    done
    if [ -n "$agent_label" ]; then
      for lbl in $all_agent_labels; do
        gh pr edit "$pr" --repo "$REPO" --remove-label "$lbl" &>/dev/null || true
      done
      gh pr edit "$pr" --repo "$REPO" --add-label "$agent_label" &>/dev/null || true
    fi
    gh pr edit "$pr" --repo "$REPO" --add-label "$status_label" &>/dev/null \
      && audit "sync_label_pr" "pr=$pr status=$status_label agent=$agent_label" \
      || echo "  ⚠ falha ao sincronizar labels no PR #$pr"
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
      echo "  ⏳ Aguardando ${wait}s..."
      sleep $wait
      wait=$((wait * 2))
    fi
  done

  echo "⚠ Board não sincronizado após $max tentativas. Execute: reconcile.sh $PROJECT $REPO"
  audit "automation_sync_failed" "board_status=$board_status retries=$max" "ERROR"
  return 0
}

# ── Verificar/criar board ─────────────────────────────────────────────────────
# FC-04 CORRIGIDO: board criado automaticamente se ausente
ensure_board_exists() {
  local owner board_name exists
  owner=$(echo "$REPO" | cut -d/ -f1)
  board_name="$PROJECT Board"

  exists=$(gh project list --owner "$owner" --format json 2>/dev/null \
    | jq -r --arg n "$board_name" '.projects[] | select(.title==$n) | .title' \
    | head -1 || true)

  if [ -z "$exists" ]; then
    echo "  📋 Board '$board_name' não encontrado — criando..."
    gh project create --owner "$owner" --title "$board_name" &>/dev/null \
      && echo "  ✔ Board criado: $board_name" \
      || echo "  ⚠ Falha ao criar board. Crie manualmente: gh project create --owner $owner --title \"$board_name\""
    audit "board_created" "board=$board_name"
  fi
}

# =============================================================================
# FC-05 CORRIGIDO: lógica movida para funções (bash não suporta 'local' em case)
# =============================================================================

handle_pr_created() {
  local dev pr_number state_with_pr lead_agent rev_msg lead_msg
  dev=$(get_issue_agent)
  pr_number="${METADATA:-}"

  state_with_pr=$(jq --arg i "$ISSUE" --arg d "$dev" --arg pr "$pr_number" \
    '.issues[$i].last_developer = $d | .issues[$i].pull_request = $pr' "$STATE_FILE")
  write_state "$state_with_pr"

  update_issue "review" "reviewer"
  sync_label "$ISSUE" "review"
  call_automation "Review"

  # Developer avisa Lead: PR pronta
  lead_agent="$PROJECT-lead"
  lead_msg="🔔 PR ABERTA: Developer finalizou Issue #$ISSUE. PR #${pr_number:-?} aguarda revisão. Acompanhe em ${PROJECT}-review."
  openclaw send --agent "$lead_agent" --message "$lead_msg" &>/dev/null \
    && echo "✔ Lead notificado sobre PR #${pr_number:-?}" \
    || echo "⚠ Não foi possível notificar lead"

  # Notifica Reviewer
  rev_msg="🔔 NOVA REVISÃO: PR #${pr_number:-?} aberta para Issue #$ISSUE. Use REVIEW_PR. Anuncie na thread ${PROJECT}-review antes de iniciar."
  openclaw send --agent "$PROJECT-reviewer" --message "$rev_msg" &>/dev/null \
    && echo "✔ Reviewer notificado" \
    || echo "⚠ Não foi possível notificar reviewer"
}

handle_blocked() {
  local current_agent last_dev dev_id dev_msg lead_msg
  current_agent=$(get_issue_agent)

  if [ "$current_agent" = "reviewer" ]; then
    last_dev=$(jq -r --arg i "$ISSUE" '.issues[$i].last_developer // "developer-1"' "$STATE_FILE")
    update_issue "blocked" "$last_dev"

    dev_id=$(map_agent_id "$last_dev")
    dev_msg="🚨 AJUSTES NECESSÁRIOS: PR da Issue #$ISSUE devolvida pelo Reviewer. Veja os comentários no GitHub e use EXECUTE_ISSUE (seção 'feedback de Review'). Anuncie na thread ${PROJECT}-dev."
    openclaw send --agent "$dev_id" --message "$dev_msg" &>/dev/null \
      || echo "  ⚠ Não foi possível notificar $dev_id"
  else
    update_issue "blocked" "lead"
  fi

  sync_label "$ISSUE" "blocked"
  call_automation "Blocked"

  # Developer (ou reviewer) avisa Lead com motivo
  lead_msg="🚨 BLOQUEIO: Issue #$ISSUE bloqueada por '${current_agent}'. Motivo: ${METADATA:-não informado}. Acesse a thread ${PROJECT}-lead para providências."
  openclaw send --agent "$PROJECT-lead" --message "$lead_msg" &>/dev/null \
    && echo "✔ Lead notificado sobre bloqueio" \
    || echo "⚠ Não foi possível notificar lead"

  echo "🚨 Issue #$ISSUE bloqueada."
}

handle_unblocked() {
  local dev_id unblock_msg lead_msg
  if [ -n "$METADATA" ] && jq -e --arg a "$METADATA" '.agents[$a].role == "developer"' "$STATE_FILE" &>/dev/null 2>&1; then
    update_issue "in_progress" "$METADATA"
    sync_label "$ISSUE" "in_progress"
    call_automation "In Progress"

    dev_id=$(map_agent_id "$METADATA")
    unblock_msg="✅ DESBLOQUEADO: Issue #$ISSUE reatribuída a você. Retome com EXECUTE_ISSUE e anuncie na thread ${PROJECT}-dev."
    openclaw send --agent "$dev_id" --message "$unblock_msg" &>/dev/null || true

    lead_msg="✅ Issue #$ISSUE desbloqueada → reatribuída para $METADATA."
    openclaw send --agent "$PROJECT-lead" --message "$lead_msg" &>/dev/null || true

    echo "✔ Issue #$ISSUE desbloqueada → $METADATA"
  else
    assign_by_capacity
    call_automation "In Progress"

    lead_msg="✅ Issue #$ISSUE desbloqueada → developer reatribuído por capacidade."
    openclaw send --agent "$PROJECT-lead" --message "$lead_msg" &>/dev/null || true

    echo "✔ Issue #$ISSUE desbloqueada → auto_assign"
  fi
}

handle_pr_merged() {
  local done_msg local_closed attempt
  release_capacity
  update_issue "done" "lead"
  sync_label "$ISSUE" "done"

  local_closed=false
  for attempt in 1 2 3; do
    if gh issue close "$ISSUE" --repo "$REPO" &>/dev/null; then
      audit "gh_issue_close" "attempt=$attempt"
      local_closed=true
      break
    fi
    sleep $((attempt * 3))
  done
  [ "$local_closed" = false ] && \
    echo "⚠ Não foi possível fechar issue #$ISSUE no GitHub. Feche manualmente." && \
    audit "gh_issue_close_failed" "retries=3" "ERROR"

  call_automation "Done"

  done_msg="🏁 Issue #$ISSUE CONCLUÍDA. PR mergeada e estado sincronizado. Ótimo trabalho!"
  openclaw send --agent "$PROJECT-developer" --message "$done_msg" &>/dev/null || true
  openclaw send --agent "$PROJECT-reviewer"  --message "$done_msg" &>/dev/null || true
  openclaw send --agent "$PROJECT-lead"      --message "$done_msg" &>/dev/null || true
}

# =============================================================================
# 🔄 Máquina de Estados
# =============================================================================

echo "▶ state-engine: project=$PROJECT issue=#$ISSUE event=$EVENT"
backup_state

case $EVENT in

  issue_created)
    ensure_board_exists
    update_issue "inbox" "product"
    sync_label "$ISSUE" "inbox"
    call_automation "Inbox"
    echo "  → auto_assign em seguida..."
    assign_by_capacity
    update_issue "in_progress" "$(get_issue_agent)"
    sync_label "$ISSUE" "in_progress"
    call_automation "In Progress"
    ;;

  auto_assign)
    ensure_board_exists
    assign_by_capacity
    call_automation "In Progress"
    ;;

  pr_created)
    handle_pr_created
    ;;

  pr_approved)
    update_issue "approved" "reviewer"
    sync_label "$ISSUE" "approved"
    call_automation "Review"
    audit "pr_approved" "awaiting_merge"
    openclaw send --agent "$PROJECT-lead" \
      --message "✅ PR aprovada para Issue #$ISSUE. Aguardando merge do usuário no GitHub." \
      &>/dev/null || true
    echo "✔ PR aprovada. Aguardando merge."
    ;;

  blocked)
    handle_blocked
    ;;

  unblocked)
    handle_unblocked
    ;;

  pr_merged)
    handle_pr_merged
    ;;

  reopened)
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
