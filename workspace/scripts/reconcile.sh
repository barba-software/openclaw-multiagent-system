#!/usr/bin/env bash
# =============================================================================
# reconcile.sh — Reconciliação estado interno ↔ GitHub
# =============================================================================
# Uso: reconcile.sh <project> <repo> [--dry-run]
#
# Detecta e corrige divergências entre state.json e GitHub:
#   - Issue marcada "done" internamente mas ainda aberta no GitHub
#   - Issue marcada "in_progress" mas fechada no GitHub
#   - Card no board com status errado vs state.json
#   - Issue em active_issues mas já done/closed
#
# --dry-run: apenas lista o que seria corrigido, sem aplicar
# =============================================================================

set -euo pipefail

PROJECT="${1:-}"
REPO="${2:-}"
DRY_RUN=false

if [ -z "$PROJECT" ] || [ -z "$REPO" ]; then
  echo "Uso: reconcile.sh <project> <repo> [--dry-run]"
  exit 1
fi

if [ "${3:-}" = "--dry-run" ]; then
  DRY_RUN=true
  echo "🔍 MODO DRY-RUN — nenhuma alteração será aplicada"
fi

# ── Token GitHub ─────────────────────────────────────────────────────────────
# Garantir que o GH_TOKEN esteja disponível para o gh CLI
export GH_TOKEN="${GH_TOKEN:-$(cat ~/.config/gh/hosts.yml 2>/dev/null | grep 'oauth_token:' | head -1 | awk '{print $2}')}"

BASE="$HOME/.openclaw/workspace/projects/$PROJECT"
STATE_FILE="$BASE/state.json"
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$STATE_FILE" ]; then
  echo "❌ state.json não encontrado: $STATE_FILE"
  exit 1
fi

echo "🔄 Reconciliação: $PROJECT ↔ $REPO"
echo ""

FIXES=0
ERRORS=0

fix() {
  local desc="$1"
  shift
  FIXES=$((FIXES+1))
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY-RUN] Aplicaria: $desc"
  else
    echo "  🔧 Corrigindo: $desc"
    "$@" || { echo "    ❌ Falhou"; ERRORS=$((ERRORS+1)); }
  fi
}

# ── Verificar cada issue registrada ──────────────────────────────────────────
while IFS= read -r issue_id; do
  status=$(jq -r --arg i "$issue_id" '.issues[$i].status' "$STATE_FILE")

  echo "Issue #$issue_id (interno: $status)"

  # Obter estado do GitHub
  gh_state=$(gh issue view "$issue_id" --repo "$REPO" --json state -q ".state" 2>/dev/null || echo "not_found")

  if [ "$gh_state" = "not_found" ]; then
    echo "  ⚠ Issue #$issue_id não encontrada no GitHub — ignorando"
    continue
  fi

  # done interno mas aberta no GitHub
  if [ "$status" = "done" ] && [ "$gh_state" = "OPEN" ]; then
    fix "Fechar issue #$issue_id no GitHub (estado interno: done)" \
      gh issue close "$issue_id" --repo "$REPO"
  fi

  # closed no GitHub mas não done internamente
  if [ "$gh_state" = "CLOSED" ] && [ "$status" != "done" ]; then
    echo "  ⚠ Issue #$issue_id fechada no GitHub mas estado interno é '$status'"
    if [ "$DRY_RUN" = false ]; then
      "$SCRIPTS_DIR/state_engine.sh" "$PROJECT" "$REPO" "$issue_id" "pr_merged" 2>/dev/null || true
      echo "    → Estado interno atualizado para 'done'"
    else
      echo "  [DRY-RUN] Atualizaria estado interno para 'done'"
    fi
    FIXES=$((FIXES+1))
  fi

  # Sincronizar card no board
  # Mapear status interno → coluna do board (bash compat, sem declare -A em subshell)
  board_status=""
  case "$status" in
	inbox) board_status="Inbox" ;;
    in_progress) board_status="In Progress" ;;
	review) board_status="Review" ;;
	approved) board_status="Review" ;;
	blocked) board_status="Blocked" ;;
    done)        board_status="Done" ;;
  esac
  if [ -n "$board_status" ]; then
    fix "Sincronizar board: issue #$issue_id → $board_status" \
      "$SCRIPTS_DIR/automation.sh" "$PROJECT" "$REPO" "$issue_id" "$board_status"
  fi

  echo ""
done < <(jq -r '.issues | keys[]' "$STATE_FILE" 2>/dev/null || true)

# ── Verificar active_issues de agentes ───────────────────────────────────────
echo "Verificando active_issues dos agentes..."
while IFS= read -r agent; do
  while IFS= read -r issue_id; do
    issue_status=$(jq -r --arg i "$issue_id" '.issues[$i].status // "not_found"' "$STATE_FILE")
    if [ "$issue_status" = "done" ] || [ "$issue_status" = "not_found" ]; then
      echo "  ⚠ $agent tem issue #$issue_id ($issue_status) em active_issues"
      fix "Remover issue #$issue_id de active_issues de $agent" \
        bash -c "jq --arg a '$agent' --arg i '$issue_id' \
          '.agents[\$a].active_issues = (.agents[\$a].active_issues | map(select(. != \$i)))' \
          '$STATE_FILE' > '${STATE_FILE}.tmp' && mv '${STATE_FILE}.tmp' '$STATE_FILE'"
    fi
  done < <(jq -r --arg a "$agent" '.agents[$a].active_issues[]' "$STATE_FILE" 2>/dev/null || true)
done < <(jq -r '.agents | keys[]' "$STATE_FILE")

echo ""
echo "────────────────────────────────────"
echo "Reconciliação concluída"
echo "  Correções: $FIXES"
echo "  Erros:     $ERRORS"
if [ "$DRY_RUN" = true ]; then
  echo "  (dry-run — nenhuma alteração aplicada)"
fi
