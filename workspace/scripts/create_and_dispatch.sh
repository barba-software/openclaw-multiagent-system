#!/usr/bin/env bash
# =============================================================================
# create_and_dispatch.sh — Cria Issue no GitHub e dispara state-engine
# =============================================================================
# Uso: create_and_dispatch.sh <project> <repo> <title> <body> [labels]
#
# Encapsula: gh issue create + state-engine issue_created + sync label
# O agente product chama este script em vez de fazer os passos manualmente
# =============================================================================

set -euo pipefail

PROJECT="${1:-}"
REPO="${2:-}"
TITLE="${3:-}"
BODY="${4:-}"
LABELS="${5:-feature}"

if [ -z "$PROJECT" ] || [ -z "$REPO" ] || [ -z "$TITLE" ] || [ -z "$BODY" ]; then
  echo "Uso: create_and_dispatch.sh <project> <repo> <title> <body> [labels]"
  exit 1
fi

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"

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

# ── Verificar duplicata ───────────────────────────────────────────────────────
echo "🔍 Verificando duplicatas..."
EXISTING=$(gh issue list --repo "$REPO" --state all \
  --search "$TITLE" --json number,title,state \
  --jq '.[] | "  #\(.number) [\(.state)] \(.title)"' 2>/dev/null || true)

if [ -n "$EXISTING" ]; then
  echo "⚠ Issues similares encontradas:"
  echo "$EXISTING"
  echo ""
  echo "  (Prosseguindo automaticamente...)"
fi

# ── Criar Issue ───────────────────────────────────────────────────────────────
echo "📝 Criando Issue..."
ISSUE_URL=$(gh issue create \
  --repo "$REPO" \
  --title "$TITLE" \
  --body "$BODY" \
  --label "$LABELS" \
  --project "$PROJECT Board" \
  2>/dev/null)

ISSUE_NUM=$(echo "$ISSUE_URL" | grep -oE '[0-9]+$')

if [ -z "$ISSUE_NUM" ]; then
  echo "❌ Falha ao criar Issue ou obter número"
  exit 1
fi

echo "✔ Issue #$ISSUE_NUM criada: $ISSUE_URL"

# ── Disparar state-engine ────────────────────────────────────────────────────
echo "⚙ Disparando state-engine (issue_created + auto_assign)..."
chmod +x "$SCRIPTS_DIR/state_engine.sh"
"$SCRIPTS_DIR/state_engine.sh" "$PROJECT" "$REPO" "$ISSUE_NUM" "issue_created"

# ── Output final para o agente ────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════"
echo "✅ Issue #$ISSUE_NUM criada e despachada"
echo "   Título: $TITLE"
echo "   URL:    $ISSUE_URL"
echo "   Status: in_progress (developer notificado)"
echo "═══════════════════════════════════════"
echo ""
echo "Postar no Discord:"
echo "✅ Issue #$ISSUE_NUM criada: $ISSUE_URL"
