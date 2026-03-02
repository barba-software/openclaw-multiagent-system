#!/usr/bin/env bash
# =============================================================================
# sync-labels.sh — Sincroniza labels do GitHub com state.json
# =============================================================================
# Uso: sync-labels.sh <project> <repo> [--dry-run]
# =============================================================================

set -euo pipefail

PROJECT="${1:-}"
REPO="${2:-}"
DRY_RUN=false
[ "${3:-}" = "--dry-run" ] && DRY_RUN=true && echo "🔍 DRY-RUN ativado"

if [ -z "$PROJECT" ] || [ -z "$REPO" ]; then
  echo "Uso: sync-labels.sh <project> <repo> [--dry-run]"
  exit 1
fi

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
[ -z "${GH_TOKEN:-}" ] && echo "❌ GH_TOKEN não definido" && exit 1

STATE_FILE="$HOME/.openclaw/workspace/projects/$PROJECT/state.json"
[ ! -f "$STATE_FILE" ] && echo "❌ state.json não encontrado: $STATE_FILE" && exit 1

ALL_LABELS="inbox in_progress review blocked done"

STATUS_TO_LABEL() {
  case "$1" in
    inbox)       echo "inbox" ;;
    in_progress) echo "in_progress" ;;
    review)      echo "review" ;;
    approved)    echo "review" ;;
    blocked)     echo "blocked" ;;
    done)        echo "done" ;;
    *)           echo "" ;;
  esac
}

echo "🏷  sync-labels: $PROJECT ↔ $REPO"
echo ""

FIXED=0

while IFS= read -r issue_id; do
  [ -z "$issue_id" ] && continue
  status=$(jq -r --arg i "$issue_id" '.issues[$i].status // empty' "$STATE_FILE")
  label=$(STATUS_TO_LABEL "$status")
  [ -z "$label" ] && continue

  echo "Issue #$issue_id → label: $label"

  if [ "$DRY_RUN" = false ]; then
    # Remover todas as labels de status
    for lbl in $ALL_LABELS; do
      gh issue edit "$issue_id" --repo "$REPO" --remove-label "$lbl" &>/dev/null || true
    done
    # Aplicar label correta
    gh issue edit "$issue_id" --repo "$REPO" --add-label "$label" &>/dev/null \
      && echo "  ✔ label $label aplicada" \
      || echo "  ⚠ falhou — verifique se a label '$label' existe no repo"
    FIXED=$((FIXED+1))
  else
    echo "  [DRY-RUN] aplicaria label: $label"
    FIXED=$((FIXED+1))
  fi

done < <(jq -r '.issues | keys[]' "$STATE_FILE" 2>/dev/null || true)

echo ""
echo "────────────────────────────────────"
echo "Issues sincronizadas: $FIXED"
[ "$DRY_RUN" = true ] && echo "(dry-run — nenhuma alteração aplicada)"
