#!/usr/bin/env bash

PROJECT=$1
REPO=$2
ISSUE_NUMBER=$3
NEW_STATUS=$4

OWNER=$(echo $REPO | cut -d/ -f1)
BOARD_NAME="$PROJECT Board"

# ==============================
# Obter Board ID
# ==============================

BOARD_ID=$(gh project list --owner "$OWNER" --format json | jq -r ".[] | select(.title==\"$BOARD_NAME\") | .id")

if [ -z "$BOARD_ID" ]; then
  echo "❌ Board não encontrado"
  exit 1
fi

# ==============================
# Obter Item ID da Issue
# ==============================

ISSUE_URL=$(gh issue view $ISSUE_NUMBER --repo "$REPO" --json url -q ".url")

ITEM_ID=$(gh project item-list "$BOARD_ID" --format json | jq -r ".items[] | select(.content.url==\"$ISSUE_URL\") | .id")

# Se item não existir → adicionar
if [ -z "$ITEM_ID" ]; then
  echo "Adicionando Issue ao board..."
  gh project item-add "$BOARD_ID" --url "$ISSUE_URL" > /dev/null
  ITEM_ID=$(gh project item-list "$BOARD_ID" --format json | jq -r ".items[] | select(.content.url==\"$ISSUE_URL\") | .id")
fi

# ==============================
# Obter Status Field ID
# ==============================

STATUS_FIELD_ID=$(gh project field-list "$BOARD_ID" --format json | jq -r ".[] | select(.name==\"Status\") | .id")

# Obter Option ID
OPTION_ID=$(gh project field-list "$BOARD_ID" --format json | jq -r ".[] | select(.name==\"Status\") | .options[] | select(.name==\"$NEW_STATUS\") | .id")

if [ -z "$OPTION_ID" ]; then
  echo "❌ Status $NEW_STATUS não encontrado"
  exit 1
fi

# ==============================
# Atualizar Status
# ==============================

gh project item-edit \
  --id "$ITEM_ID" \
  --field-id "$STATUS_FIELD_ID" \
  --single-select-option-id "$OPTION_ID" > /dev/null

echo "✔ Issue #$ISSUE_NUMBER movida para $NEW_STATUS"
