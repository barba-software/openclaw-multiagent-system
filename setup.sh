#!/usr/bin/env bash
# =============================================================================
# setup.sh — Configura o OpenClaw Multi-Agent System
#
# Execute este script de dentro do diretório clonado:
#   cd ~/.openclaw/openclaw-multiagent-system
#   bash setup.sh
# =============================================================================
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="$HOME/.openclaw/workspace"

echo "================================================="
echo "   OpenClaw Multi-Agent System — Setup"
echo "================================================="
echo ""

# ---------------------------------------------------------------------------
# 1. Validar estrutura do repositório clonado
# ---------------------------------------------------------------------------
MISSING=0
[ ! -d "$REPO_DIR/agents" ]             && echo "ERRO: pasta 'agents/' não encontrada em $REPO_DIR"             && MISSING=1
[ ! -d "$REPO_DIR/workspace/skills" ]   && echo "ERRO: pasta 'workspace/skills/' não encontrada em $REPO_DIR"   && MISSING=1
[ ! -d "$REPO_DIR/workspace/scripts" ]  && echo "ERRO: pasta 'workspace/scripts/' não encontrada em $REPO_DIR"  && MISSING=1

if [ "$MISSING" -eq 1 ]; then
  echo ""
  echo "Verifique se você está executando o setup.sh de dentro do diretório correto do repositório."
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Solicitar nome do agente principal (Lead / Gerente Geral)
# ---------------------------------------------------------------------------
echo "Qual será o nome do agente principal (Lead / Gerente Geral)?"
echo "Exemplo: Max, Maria, Aria, Command..."
echo ""
read -rp "Nome do agente principal: " MAIN_NAME

if [ -z "$MAIN_NAME" ]; then
  echo "ERRO: O nome do agente principal não pode ser vazio."
  exit 1
fi

# ---------------------------------------------------------------------------
# 3. Copiar arquivos para ~/.openclaw/workspace/
# ---------------------------------------------------------------------------
echo ""
echo "Copiando arquivos para $TARGET ..."

mkdir -p "$TARGET/agents"
mkdir -p "$TARGET/skills"
mkdir -p "$TARGET/scripts"

cp -R "$REPO_DIR/agents/"*            "$TARGET/agents/"
cp -R "$REPO_DIR/workspace/skills/"*  "$TARGET/skills/"
cp -R "$REPO_DIR/workspace/scripts/"* "$TARGET/scripts/"
chmod +x "$TARGET/scripts/"*.sh 2>/dev/null || true

echo "  ✓ agents/   → $TARGET/agents/"
echo "  ✓ skills/   → $TARGET/skills/"
echo "  ✓ scripts/  → $TARGET/scripts/"

# ---------------------------------------------------------------------------
# 4. Copiar os arquivos do agente principal para a raiz do workspace
#    e substituir {MAIN_NAME} pelo nome informado
# ---------------------------------------------------------------------------
echo ""
echo "Configurando agente principal '$MAIN_NAME' no workspace..."

WORKSPACE_AGENTS=(AGENTS.md HEARTBEAT.md IDENTITY.md SOUL.md USER.md WORKING.md)
for FILE in "${WORKSPACE_AGENTS[@]}"; do
  SRC="$REPO_DIR/workspace/$FILE"
  DST="$TARGET/$FILE"
  if [ -f "$SRC" ]; then
    sed "s/{MAIN_NAME}/$MAIN_NAME/g" "$SRC" > "$DST"
    echo "  ✓ $FILE → $TARGET/"
  else
    echo "  AVISO: $SRC não encontrado, ignorando."
  fi
done

# ---------------------------------------------------------------------------
# 5. Concluído
# ---------------------------------------------------------------------------
echo ""
echo "================================================="
echo " Setup concluído!"
echo "================================================="
echo ""
echo "Próximos passos:"
echo "  1. Peça ao agente principal '$MAIN_NAME' para provisionar um projeto:"
echo "     'provisionar projeto meu-projeto'"
echo "  2. Siga as instruções da skill start_project."
echo ""
