#!/usr/bin/env bash
# =============================================================================
# inbox-dispatch.sh — Dispara auto_assign para todas as issues em Inbox
# =============================================================================
# Uso: inbox-dispatch.sh <project> <repo> [--dry-run]
#
# Busca issues com label "inbox" no GitHub e dispara auto_assign no state-engine
# para cada uma que ainda não está em progresso no state.json
# =============================================================================

set -euo pipefail

PROJECT="${1:-}"
REPO="${2:-}"
DRY_RUN=false

if [ -z "$PROJECT" ] || [ -z "$REPO" ]; then
  echo "Uso: inbox-dispatch.sh <project> <repo> [--dry-run]"
  exit 1
fi

[ "${3:-}" = "--dry-run" ] && DRY_RUN=true && echo "🔍 DRY-RUN ativado"

# ── Autenticação GitHub ────────────────────────────────────────────────────────
# Prioridade: GH_TOKEN env > GITHUB_TOKEN env > token salvo pelo gh auth
if [ -n "${GH_TOKEN:-}" ]; then
  export GH_TOKEN
elif [ -n "${GITHUB_TOKEN:-}" ]; then
  export GH_TOKEN="$GITHUB_TOKEN"
elif [ -f "$HOME/.config/gh/hosts.yml" ]; then
  _token=$(grep -A2 "github.com" "$HOME/.config/gh/hosts.yml"     | grep "oauth_token" | awk '{print $2}' | head -1 || true)
  [ -n "$_token" ] && export GH_TOKEN="$_token"
fi

if [ -z "${GH_TOKEN:-}" ]; then
  echo "❌ Token GitHub não encontrado."
  echo "   Export: GH_TOKEN=seu_token"
  exit 1
fi

if ! gh auth status &>/dev/null; then
  echo "❌ gh CLI não autenticado mesmo com GH_TOKEN"
  echo "   Tente: echo \$GH_TOKEN | gh auth login --with-token"
  exit 1
fi

BASE="$HOME/.openclaw/workspace/projects/$PROJECT"
STATE_FILE="$BASE/state.json"
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"

# Inicializar state.json se não existir
if [ ! -f "$STATE_FILE" ]; then
  echo "⚠ state.json não encontrado — inicializando..."
  "$SCRIPTS_DIR/state_engine.sh" "$PROJECT" "$REPO" "0" "issue_created" 2>/dev/null || true
fi

echo "📋 inbox-dispatch: $PROJECT ↔ $REPO"
echo ""

# Buscar issues abertas com label inbox no GitHub
ISSUES_INBOX=$(gh issue list --repo "$REPO" --label "inbox" --state open --json number --jq '.[].number' 2>/dev/null || true)

# Também buscar todas as issues abertas não atribuídas (sem assignee)
# para cobrir issues criadas manualmente sem passar pelo state-engine
ISSUES_ALL=$(gh issue list --repo "$REPO" --state open --json number --jq '.[].number' 2>/dev/null || true)

# Unir as duas listas sem duplicatas
ISSUES=$(printf "%s
%s" "$ISSUES_INBOX" "$ISSUES_ALL" | sort -n | uniq)

if [ -z "$ISSUES" ]; then
  echo "  ✔ Nenhuma issue aberta encontrada"
  exit 0
fi

echo "  Issues abertas encontradas: $(echo "$ISSUES" | wc -l | tr -d ' ')"
echo ""

COUNT=0
DISPATCHED=0

while IFS= read -r issue_id; do
  # Pular linhas vazias
  [ -z "$issue_id" ] && continue
  # Pular se não for número
  [[ "$issue_id" =~ ^[0-9]+$ ]] || continue

  COUNT=$((COUNT+1))
  
  # Verificar se já está no state.json e qual o status
  current_status=$(jq -r --arg i "$issue_id" '.issues[$i].status // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
  
  echo "Issue #$issue_id (state: $current_status)"
  
  case "$current_status" in
    in_progress|review|approved|done)
      echo "  ⚠ já em '$current_status' — pulando"
      ;;
    unknown)
      # Nunca passou pelo state-engine — registrar como issue_created e auto_assign
      echo "  → não está no state.json — registrando e atribuindo..."
      if [ "$DRY_RUN" = false ]; then
        chmod +x "$SCRIPTS_DIR/state_engine.sh"
        "$SCRIPTS_DIR/state_engine.sh" "$PROJECT" "$REPO" "$issue_id" "issue_created"
        DISPATCHED=$((DISPATCHED+1))
      else
        echo "  [DRY-RUN] Rodaria: state-engine issue_created + auto_assign"
        DISPATCHED=$((DISPATCHED+1))
      fi
      ;;
    inbox)
      # Está no state mas parou no inbox — disparar auto_assign
      echo "  → parada em inbox — disparando auto_assign..."
      if [ "$DRY_RUN" = false ]; then
        chmod +x "$SCRIPTS_DIR/state_engine.sh"
        "$SCRIPTS_DIR/state_engine.sh" "$PROJECT" "$REPO" "$issue_id" "auto_assign"
        DISPATCHED=$((DISPATCHED+1))
      else
        echo "  [DRY-RUN] Rodaria: state-engine auto_assign"
        DISPATCHED=$((DISPATCHED+1))
      fi
      ;;
    blocked)
      echo "  ⚠ bloqueada — não será auto-atribuída (resolva o bloqueio primeiro)"
      ;;
  esac
  echo ""
done <<< "$ISSUES"

echo "────────────────────────────────────"
echo "Issues encontradas: $COUNT"
echo "Despachadas:        $DISPATCHED"
[ "$DRY_RUN" = true ] && echo "(dry-run — nenhuma alteração aplicada)"

# DEBUG TEMPORÁRIO — remover após confirmar
echo "=== DEBUG ==="
echo "gh issue list raw:"
gh issue list --repo "$REPO" --state open --json number,title,labels 2>&1 | head -20
echo "gh auth status:"
gh auth status 2>&1
