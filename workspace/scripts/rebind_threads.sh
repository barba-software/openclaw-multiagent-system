#!/usr/bin/env bash
# =============================================================================
# rebind_threads.sh — Sincroniza agentes existentes com a nova estrutura de threads
# =============================================================================
# Uso: ./rebind_threads.sh <nome_projeto> <canal_principal_discord>
# =============================================================================
set -euo pipefail

PROJECT="${1:-}"
CHANNEL="${2:-}"

if [ -z "$PROJECT" ] || [ -z "$CHANNEL" ]; then
    echo "Uso: ./rebind_threads.sh <nome_projeto> <canal_principal_discord>"
    echo "Exemplo: ./rebind_threads.sh quemresolve quemresolve-geral"
    exit 1
fi

# Normaliza canal
CHANNEL="${CHANNEL#\#}"

echo "🔄 Re-vinculando agentes do projeto [$PROJECT] às threads..."

# 1. Product -> Canal Principal
openclaw agents bind --agent "${PROJECT}-product" --bind "discord:${CHANNEL}"
echo "  ✔ ${PROJECT}-product -> discord:${CHANNEL}"

# 2. Lead -> Thread lead
openclaw agents bind --agent "${PROJECT}-lead" --bind "discord:lead"
echo "  ✔ ${PROJECT}-lead -> discord:lead"

# 3. Developer -> Thread squad
openclaw agents bind --agent "${PROJECT}-developer" --bind "discord:squad"
echo "  ✔ ${PROJECT}-developer -> discord:squad"

# 4. Reviewer -> Thread squad
openclaw agents bind --agent "${PROJECT}-reviewer" --bind "discord:squad"
echo "  ✔ ${PROJECT}-reviewer -> discord:squad"

echo ""
echo "✅ Sincronização de threads finalizada para o projeto $PROJECT!"
echo "Certifique-se de que as threads 'squad' e 'lead' foram criadas no Discord."
