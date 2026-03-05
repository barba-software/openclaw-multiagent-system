#!/usr/bin/env bash

# =============================================================================
# automation.sh — Sincronização com GitHub Projects
# =============================================================================
# Uso: automation.sh <project> <repo> <issue_number> <status>
#
# Responsabilidade: APENAS sincronizar o board do GitHub com o estado
# que o state-engine decidiu. Nunca toma decisões de negócio.
# =============================================================================

set -euo pipefail

PROJECT="${1:-}"
REPO="${2:-}"
ISSUE_NUMBER="${3:-}"
NEW_STATUS="${4:-}"

if [ -z "$PROJECT" ] || [ -z "$REPO" ] || [ -z "$ISSUE_NUMBER" ] || [ -z "$NEW_STATUS" ]; then
  echo "Uso: automation.sh <project> <repo> <issue_number> <new_status>"
  echo "Status válidos: Inbox | In Progress | Review | Blocked | Done"
  exit 1
fi

# ── Dependências ──────────────────────────────────────────────────────────────
if ! command -v gh &>/dev/null; then
  echo "❌ GitHub CLI (gh) não encontrado"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "❌ jq não encontrado"
  exit 1
fi

OWNER=$(echo "$REPO" | cut -d/ -f1)
BOARD_NAME="$PROJECT Board"

# ── Verificar autenticação ────────────────────────────────────────────────────
if ! gh auth status &>/dev/null; then
  echo "❌ GitHub CLI não autenticado. Execute: gh auth login"
  exit 1
fi

# ── Obter Board via GraphQL (gh project list --owner falha sem escopo interativo) ──
GH_LOGIN=$(gh api user --jq .login 2>/dev/null || true)

_get_owner_node_id() {
  local id
  id=$(gh api "orgs/$OWNER" --jq .node_id 2>/dev/null) && echo "$id" && return
  gh api "users/$OWNER" --jq .node_id 2>/dev/null || true
}

OWNER_NODE_ID=$(_get_owner_node_id)
if [ -z "$OWNER_NODE_ID" ]; then
  echo "❌ Não foi possível obter node_id do owner $OWNER"
  exit 1
fi

_TMP_BOARD=$(mktemp)
gh api graphql -f query="
  query {
    node(id: \"$OWNER_NODE_ID\") {
      ... on User         { projectsV2(first:20) { nodes { id number title closed } } }
      ... on Organization { projectsV2(first:20) { nodes { id number title closed } } }
    }
  }
" 2>/dev/null > "$_TMP_BOARD" || true

BOARD_JSON=$(jq -rc ".data.node.projectsV2.nodes[] | select(.title == \"$BOARD_NAME\" and .closed == false)"   "$_TMP_BOARD" 2>/dev/null | head -1 || true)
rm -f "$_TMP_BOARD"

if [ -z "$BOARD_JSON" ]; then
  echo "❌ Board '$BOARD_NAME' não encontrado para owner '$OWNER'"
  echo "  Crie o board com: provision.sh $PROJECT $REPO <discord_channel>"
  exit 1
fi

BOARD_ID=$(echo "$BOARD_JSON" | jq -r '.id')
BOARD_NUMBER=$(echo "$BOARD_JSON" | jq -r '.number')

# ── Obter URL da Issue ─────────────────────────────────────────────────────────
ISSUE_URL=$(gh issue view "$ISSUE_NUMBER" --repo "$REPO" --json url -q ".url" 2>/dev/null || true)
if [ -z "$ISSUE_URL" ]; then
  echo "❌ Issue #$ISSUE_NUMBER não encontrada no repo $REPO"
  exit 1
fi

# ── Obter ou criar Item no Board via GraphQL ──────────────────────────────────
# Buscar item com paginação (suporta boards com >100 issues)
_find_board_item() {
  local board_id="$1" issue_url="$2" cursor="" found=""
  local page=0
  while [ $page -lt 20 ]; do  # max 2000 items
    page=$((page+1))
    local after_arg=""
    [ -n "$cursor" ] && after_arg=", after: \\\"$cursor\\\""
    local _tmp
    _tmp=$(mktemp)
    gh api graphql -f query="
      query {
        node(id: \"$board_id\") {
          ... on ProjectV2 {
            items(first: 100$after_arg) {
              pageInfo { hasNextPage endCursor }
              nodes { id content { ... on Issue { url } } }
            }
          }
        }
      }
    " 2>/dev/null > "$_tmp" || true
    found=$(jq -r ".data.node.items.nodes[] | select(.content.url == \"$issue_url\") | .id" \
      "$_tmp" 2>/dev/null | head -1 || true)
    local has_next
    has_next=$(jq -r '.data.node.items.pageInfo.hasNextPage // false' "$_tmp" 2>/dev/null || echo false)
    cursor=$(jq -r '.data.node.items.pageInfo.endCursor // empty' "$_tmp" 2>/dev/null || true)
    rm -f "$_tmp"
    [ -n "$found" ] && echo "$found" && return 0
    [ "$has_next" = "false" ] && break
  done
  echo ""
}

ITEM_ID=$(_find_board_item "$BOARD_ID" "$ISSUE_URL")

if [ -z "$ITEM_ID" ]; then
  echo "  ➕ Issue não está no board — adicionando..."
  gh project item-add "$BOARD_NUMBER" --owner "$OWNER" --url "$ISSUE_URL" >/dev/null
  sleep 2
  ITEM_ID=$(_find_board_item "$BOARD_ID" "$ISSUE_URL")
  if [ -z "$ITEM_ID" ]; then
    echo "❌ Falha ao obter item do board após adicionar"
    exit 1
  fi
fi

# ── Obter Status Field ID e Option ID via GraphQL ─────────────────────────────
_TMP_FIELDS=$(mktemp)
gh api graphql -f query="
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
" 2>/dev/null > "$_TMP_FIELDS" || true

STATUS_FIELD_ID=$(jq -r   '.data.node.fields.nodes[] | select(.name == "Status") | .id'   "$_TMP_FIELDS" 2>/dev/null || true)

OPTION_ID=$(jq -r   ".data.node.fields.nodes[] | select(.name == \"Status\") | .options[] | select(.name == \"$NEW_STATUS\") | .id"   "$_TMP_FIELDS" 2>/dev/null | head -1 || true)
rm -f "$_TMP_FIELDS"

if [ -z "$STATUS_FIELD_ID" ]; then
  echo "❌ Campo 'Status' não encontrado no board"
  exit 1
fi

if [ -z "$OPTION_ID" ]; then
  echo "❌ Opção '$NEW_STATUS' não encontrada no campo Status"
  echo "  Opções esperadas: Inbox | In Progress | Review | Blocked | Done"
  exit 1
fi

# ── Atualizar Status (usa BOARD_ID global para --project-id) ────────────────────
gh project item-edit \
  --id "$ITEM_ID" \
  --field-id "$STATUS_FIELD_ID" \
  --single-select-option-id "$OPTION_ID" \
  --project-id "$BOARD_ID" >/dev/null

echo "✔ Issue #$ISSUE_NUMBER → $NEW_STATUS (board: $BOARD_NAME)"
