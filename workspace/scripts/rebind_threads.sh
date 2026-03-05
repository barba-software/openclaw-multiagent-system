#!/usr/bin/env bash
# =============================================================================
# rebind_threads.sh — Sincroniza agentes existentes com a nova estrutura de threads
# =============================================================================
# Uso: ./rebind_threads.sh <nome_projeto> <canal_principal_discord>
# =============================================================================
set -euo pipefail

PROJECT="${1:-}"
CHANNEL="${2:-}"
DISCORD_GUILD_ID="${3:-}"

if [ -z "$PROJECT" ] || [ -z "$CHANNEL" ] || [ -z "$DISCORD_GUILD_ID" ]; then
    echo "Uso: ./rebind_threads.sh <nome_projeto> <canal_principal_discord> <discord_guild_id>"
    echo "Exemplo: ./rebind_threads.sh quemresolve quemresolve-geral 123456789"
    exit 1
fi

export DISCORD_GUILD_ID
# Normaliza canal
CHANNEL="${CHANNEL#\#}"

echo "🔄 Re-vinculando agentes do projeto [$PROJECT] às threads..."

# 1. Product -> Canal Principal
openclaw agents bind --agent "${PROJECT}-product" --bind "discord:${CHANNEL}"
echo "  ✔ ${PROJECT}-product -> discord:${CHANNEL}"

# 2. Lead -> Thread lead
openclaw agents bind --agent "${PROJECT}-lead" --bind "discord:${PROJECT}-lead"
echo "  ✔ ${PROJECT}-lead -> discord:${PROJECT}-lead"

# 3. Developer -> Thread squad
openclaw agents bind --agent "${PROJECT}-developer" --bind "discord:${PROJECT}-dev"
echo "  ✔ ${PROJECT}-developer -> discord:${PROJECT}-dev"

# 4. Reviewer -> Thread squad
openclaw agents bind --agent "${PROJECT}-reviewer" --bind "discord:${PROJECT}-review"
echo "  ✔ ${PROJECT}-reviewer -> discord:${PROJECT}-review"

echo ""
echo "✅ Sincronização de threads finalizada para o projeto $PROJECT!"
echo "Certifique-se de que as threads 'squad' e 'lead' foram criadas no Discord."
