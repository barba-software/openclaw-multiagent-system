#!/usr/bin/env bash
# =============================================================================
# install.sh — Wizard interativo de instalação do OpenClaw Multi-Agent System
# =============================================================================
set -e

echo "================================================="
echo "   🚀 Instalador OpenClaw Multi-Agent System"
echo "================================================="
echo "Este wizard fará o download da arquitetura, copiará"
echo "as skills e executará o provisionamento dos agentes."
echo ""

# 1. Checagem de ferramentas
for cmd in git gh jq openclaw; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "❌ Erro: O comando '$cmd' não foi encontrado."
        echo "Por favor, instale-o antes de prosseguir."
        exit 1
    fi
done

# 2. Clonagem local num repositório central provisório pro OpenClaw
INSTALL_DIR="$HOME/.openclaw/templates/multiagent-system"
echo " Baixando/Atualizando templates oficiais do sistema..."
if [ ! -d "$INSTALL_DIR" ]; then
    git clone https://github.com/barba-software/openclaw-multiagent-system.git "$INSTALL_DIR" --quiet
else
    cd "$INSTALL_DIR"
    git pull origin main --quiet
fi

# 3. Inputs interativos
echo ""
echo "🧩 Vamos provisionar um novo esquadrão!"
read -p "Nome do Projeto (ex: meu-backend): " PROJECT_NAME
read -p "Repositório GitHub (owner/repo): " GITHUB_REPO
read -p "Canal do Discord (sem #): " DISCORD_CHANNEL

if [ -z "$PROJECT_NAME" ] || [ -z "$GITHUB_REPO" ] || [ -z "$DISCORD_CHANNEL" ]; then
    echo "❌ Erro: Todos os dados devem ser preenchidos."
    exit 1
fi

# 4. Copiar as skills globais para o openclaw workspace (para uso das skills por todos os projetos)
echo ""
echo "⚙️ Instalando Skills (ferramentas) no OpenClaw central..."
mkdir -p "$HOME/.openclaw/workspace/skills"
mkdir -p "$HOME/.openclaw/workspace/scripts"
cp -R "$INSTALL_DIR/workspace/skills/"* "$HOME/.openclaw/workspace/skills/"
cp -R "$INSTALL_DIR/workspace/scripts/"* "$HOME/.openclaw/workspace/scripts/"

# 5. Executar o Provisionamento (AGENTS, HEARTBEAT, CRONS e BOARD)
echo "⚙️ Iniciando o provisionamento dos agentes ($PROJECT_NAME)..."
cd "$INSTALL_DIR/workspace/scripts"
bash provision.sh "$PROJECT_NAME" "$GITHUB_REPO" "$DISCORD_CHANNEL"

echo ""
echo "================================================="
echo " 🎉 INSTALAÇÃO FINALIZADA COM SUCESSO!"
echo "================================================="
echo "- Agentes criados no config do openclaw"
echo "- Skills injetadas em ~/.openclaw/workspace/skills"
echo "- Cron jobs ligados"
echo "Vá para o canal #$DISCORD_CHANNEL e mande um 'oi' para o Product Agent!"
