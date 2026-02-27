#!/usr/bin/env bash

set -e

PROJECT=$1
REPO=$2
ISSUE=$3
EVENT=$4

BASE="/workspace/projects/$PROJECT"
STATE_FILE="$BASE/state.json"
LOCK_FILE="$BASE/state.lock"

if [ -z "$PROJECT" ] || [ -z "$REPO" ] || [ -z "$ISSUE" ] || [ -z "$EVENT" ]; then
  echo "Uso: state-engine.sh <project> <repo> <issue> <event>"
  exit 1
fi

# ==========================================
# 🔒 Lock (evita concorrência)
# ==========================================

exec 9>$LOCK_FILE
flock -n 9 || { echo "State em uso..."; exit 1; }

# ==========================================
# 🧠 Inicializar state.json
# ==========================================

if [ ! -f "$STATE_FILE" ]; then
  echo "Criando state.json..."
 echo "{
    \"project\": \"$PROJECT\",
    \"repo\": \"$REPO\",
    \"created_at\": \"$(date -Iseconds)\",
    \"agents\": {
      \"developer-1\": { \"role\": \"developer\", \"capacity\": 2, \"active_issues\": [] },
      \"developer-2\": { \"role\": \"developer\", \"capacity\": 2, \"active_issues\": [] }
    },
    \"issues\": {}
  }" > "$STATE_FILE"
fi

NOW=$(date -Iseconds)

# ==========================================
# 🎯 Função atualizar status
# ==========================================

update_issue () {
  STATUS=$1
  AGENT=$2

  jq "
  .issues[\"$ISSUE\"] |= (
    . // {} |
    .status = \"$STATUS\" |
    .assigned_agent = \"$AGENT\" |
    .updated_at = \"$NOW\"
  )" "$STATE_FILE" > tmp && mv tmp "$STATE_FILE"
}

# ==========================================
# 🎯 Função associar por capacidade
# ==========================================

assign_by_capacity () {
  DEV=$(jq -r '
    .agents
    | to_entries
    | map(select(.value.role=="developer"))
    | map(select(.value.active_issues | length < .value.capacity))
    | sort_by(.value.active_issues | length)
    | .[0].key' "$STATE_FILE")

  if [ "$DEV" == "null" ] || [ -z "$DEV" ]; then
    echo "Nenhum developer disponível"
    exit 1
  fi

  jq "
  .issues[\"$ISSUE\"] = {
    status: \"in_progress\",
    assigned_agent: \"$DEV\",
    created_at: \"$NOW\",
    updated_at: \"$NOW\"
  } |
  .agents[\"$DEV\"].active_issues += [$ISSUE]
  " "$STATE_FILE" > tmp && mv tmp "$STATE_FILE"

  echo "Issue #$ISSUE atribuída para $DEV"
}

# ==========================================
# 🔄 State Machine
# ==========================================

case $EVENT in

  issue_created)
    update_issue "inbox" "product"
    /workspace/scripts/automation.sh $PROJECT $REPO $ISSUE "Inbox"
    ;;

  auto_assign)
    assign_by_capacity
    ;;

  dev_started)
    update_issue "in_progress" "developer"
    /workspace/scripts/automation.sh $PROJECT $REPO $ISSUE "In Progress"
    ;;

  pr_created)
    update_issue "review" "reviewer"
    /workspace/scripts/automation.sh $PROJECT $REPO $ISSUE "Review"
    ;;

  blocked)
    update_issue "blocked" "developer"
    /workspace/scripts/automation.sh $PROJECT $REPO $ISSUE "Blocked"
    ;;

  pr_merged)
    update_issue "done" "lead"
    gh issue close $ISSUE --repo $REPO
    /workspace/scripts/automation.sh $PROJECT $REPO $ISSUE "Done"
    ;;

  *)
    echo "Evento desconhecido"
    exit 1
    ;;

esac

echo "✔ Estado atualizado: Issue #$ISSUE → $EVENT"
