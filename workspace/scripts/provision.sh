#!/usr/bin/env bash
# =============================================================================
# provision.sh — Provisionamento completo de um projeto OpenClaw
# =============================================================================
# Uso: provision.sh <nome_projeto> <owner/repo> <discord_channel>
#
# Idempotente: seguro para reexecutar sem efeitos colaterais.
# =============================================================================
set -euo pipefail
PROJECT="${1:-}"
REPO="${2:-}"
DISCORD_CHANNEL="${3:-}"
if [ -z "$PROJECT" ] || [ -z "$REPO" ] || [ -z "$DISCORD_CHANNEL" ]; then
    echo "Uso: provision.sh <nome_projeto> <owner/repo> <discord_channel>"
    echo ""
    echo "Exemplo:"
    echo "  ./provision.sh quemresolve barba-software/quemresolve-backend quemresolvebackend"
    echo ""
    echo "  Passe o nome do canal sem #"
    exit 1
fi
# Normaliza: remove # caso venha com ele
DISCORD_CHANNEL="${DISCORD_CHANNEL#\#}"
# Credenciais Discord — obrigatórias para criar/validar o canal
DISCORD_BOT_TOKEN="${DISCORD_BOT_TOKEN:-}"
DISCORD_GUILD_ID="${DISCORD_GUILD_ID:-}"
OWNER=$(echo "$REPO" | cut -d/ -f1)
BASE_DIR="$HOME/.openclaw/workspace/projects/$PROJECT"
AGENT_WS_BASE="$BASE_DIR/agents"
REGISTRY="$HOME/.openclaw/workspace/registry.json"
SCRIPTS_DIR="$HOME/.openclaw/workspace/scripts"
LOCAL_AGENTS_DIR="$HOME/.openclaw/workspace/agents"
NOW=$(date -Iseconds)
CRONS_PENDING=0

# Garantir que os scripts auxiliares sejam executáveis
chmod +x "$SCRIPTS_DIR"/*.sh 2>/dev/null || true

echo "🚀 Provisionando projeto: $PROJECT"
echo "   Repo:    $REPO"
echo "   Discord: #$DISCORD_CHANNEL"
echo ""
# -- Funções utilitárias --
ok()   { echo "  ✔ $1"; }
skip() { echo "  ⚠ $1 (já existe)"; }
fail() { echo "  ❌ $1"; exit 1; }
create_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then mkdir -p "$dir" && ok "dir: $dir"
    else skip "dir: $dir"; fi
}
create_file() {
    local file="$1" content="$2"
    if [ ! -f "$file" ]; then printf '%s\n' "$content" > "$file" && ok "file: $(basename "$file")"
    else skip "file: $(basename "$file")"; fi
}
apply_template() {
    local file="$1"
    local agent_name="$2"
    sed -e "s|{{PROJECT}}|$PROJECT|g" \
        -e "s|{{REPO}}|$REPO|g" \
        -e "s|{{DISCORD_CHANNEL}}|$DISCORD_CHANNEL|g" \
        -e "s|{{NAME}}|$agent_name|g" \
        -e "s|{{NOW}}|$NOW|g" \
        "$file"
}
# -- Criar e popular workspace de um agente --
# Uso: setup_agent_workspace <role> <name> <emoji> <theme>
setup_agent_workspace() {
    local role="$1"
    local name="$2"
    local emoji="$3"
    local theme="$4"
    local agent_id="${PROJECT}-${role}"
    local ws="$AGENT_WS_BASE/$role"
    mkdir -p "$ws"
    
    for doc in IDENTITY.md SOUL.md AGENTS.md HEARTBEAT.md USER.md WORKING.md; do
        if [ ! -f "$LOCAL_AGENTS_DIR/$role/$doc" ]; then
            fail "Arquivo template ausente: $LOCAL_AGENTS_DIR/$role/$doc"
        fi
        
        local content
        content=$(apply_template "$LOCAL_AGENTS_DIR/$role/$doc" "$name")
        create_file "$ws/$doc" "$content"
        
        # O OpenClaw exige que o IDENTITY.md tbm fique na pasta paralela .template
        if [ "$doc" = "IDENTITY.md" ]; then
            mkdir -p "$ws/.template"
            create_file "$ws/.template/IDENTITY.md" "$content"
        fi
    done

    ok "workspace populado: $agent_id"
}
# -- Registrar agente no OpenClaw e fazer bind --
create_agent() {
    local role="$1"
    local agent_id="${PROJECT}-${role}"
    local ws="$AGENT_WS_BASE/$role"
    # Sempre deletar e recriar — garante workspace e identidade corretos
    if openclaw agents list 2>/dev/null | grep -q "^$agent_id\b"; then
        # Tentar delete com --force primeiro, fallback sem flag
        if openclaw agents delete "$agent_id" --force 2>/dev/null; then
            ok "agent removido: $agent_id"
        elif openclaw agents delete "$agent_id" 2>/dev/null; then
            ok "agent removido: $agent_id"
        else
            echo "  ⚠ delete falhou para $agent_id — tentando sobrescrever com agents add"
        fi
    fi
    # Se ainda existir após delete, agents add vai falhar — remover do config diretamente
    if openclaw agents list 2>/dev/null | grep -q "^$agent_id\b"; then
        echo "  ⚠ $agent_id ainda existe após delete — forçando remoção do config"
        # Remover do openclaw.json via jq como fallback
        local config="$HOME/.openclaw/openclaw.json"
        if [ -f "$config" ]; then
            local tmp
            tmp=$(mktemp)
            jq "del(.agents.list[] | select(.id == \"$agent_id\"))" "$config" > "$tmp" \
                && mv "$tmp" "$config" \
                && ok "agent removido do config: $agent_id" \
                || echo "  ⚠ falha ao remover do config — abortando criação de $agent_id"
        fi
    fi
    # agents add — captura erro "already exists" caso delete tenha falhado silenciosamente
    local add_out add_exit
    add_out=$(openclaw agents add "$agent_id" --workspace "$ws" 2>&1) && add_exit=0 || add_exit=$?
    if [ $add_exit -eq 0 ]; then
        ok "agent criado: $agent_id (workspace: $ws)"
    elif echo "$add_out" | grep -qi "already exists"; then
        echo "  ⚠ $agent_id ainda existe — forçando remoção direta do config"
        local config="$HOME/.openclaw/openclaw.json"
        local tmp
        tmp=$(mktemp)
        jq "del(.agents.list[] | select(.id == \"$agent_id\"))" "$config" > "$tmp" \
            && mv "$tmp" "$config" \
            && ok "removido do config: $agent_id"
        # Tentar criar novamente
        openclaw agents add "$agent_id" --workspace "$ws" \
            && ok "agent criado: $agent_id (workspace: $ws)" \
            || fail "não foi possível criar $agent_id mesmo após forçar remoção"
    else
        fail "agents add falhou para $agent_id: $add_out"
    fi
    # Aplicar identidade — workspace explícito para ler IDENTITY.md do path correto
    openclaw agents set-identity --workspace "$ws" --from-identity 2>/dev/null \
        && ok "identity aplicada: $agent_id" \
        || echo "  ⚠ identity: $agent_id falhou — verifique $ws/IDENTITY.md"
    # Bind ao canal Discord
    if [ "$role" = "product" ]; then
        # Product agent escuta o canal principal (Escuta Ativa)
        openclaw agents bind --agent "$agent_id" --bind "discord:$DISCORD_CHANNEL"
        ok "bind: $agent_id → discord:$DISCORD_CHANNEL (main channel)"
    elif [ "$role" = "lead" ]; then
        # Lead agent escuta sua própria thread exclusiva
        local lead_thread="lead"
        openclaw agents bind --agent "$agent_id" --bind "discord:$lead_thread"
        ok "bind: $agent_id → discord:$lead_thread (lead thread)"
    else
        # Developer e Reviewer escutam a thread de squad (técnica)
        local squad_thread="squad"
        openclaw agents bind --agent "$agent_id" --bind "discord:$squad_thread"
        ok "bind: $agent_id → discord:$squad_thread (squad thread)"
    fi
}
# -- Criar cron --
create_cron() {
    local name="$1" agent_id="$2" schedule_flag="$3" schedule_value="$4" message="$5"
    # Sempre deletar e recriar — garante agente e mensagem atualizados
    if openclaw cron list 2>/dev/null | grep -q "\"$name\""; then
        local del_out del_exit
        del_out=$(openclaw cron delete "$name" 2>&1) && del_exit=0 || del_exit=$?
        if [ $del_exit -eq 0 ]; then
            ok "cron removido: $name"
        else
            # Tentar por ID caso o comando use id em vez de name
            local cron_id
            cron_id=$(openclaw cron list --json 2>/dev/null | jq -r ".[] | select(.name == \"$name\") | .id" 2>/dev/null || true)
            if [ -n "$cron_id" ]; then
                openclaw cron delete "$cron_id" 2>/dev/null && ok "cron removido: $name (id: $cron_id)" || true
            fi
        fi
    fi
    # shellcheck disable=SC2086
    local cron_output cron_exit
    cron_output=$(openclaw cron add \
        --name        "$name" \
        --agent       "$agent_id" \
        $schedule_flag "$schedule_value" \
        --session     isolated \
        --message     "$message" \
        --no-deliver 2>&1) && cron_exit=0 || cron_exit=$?
    if [ $cron_exit -eq 0 ]; then
        ok "cron: $name ($schedule_value)"
    elif echo "$cron_output" | grep -qi "token mismatch\|unauthorized\|gateway"; then
        echo "  ⚠ cron: $name — gateway offline (token mismatch)"
        CRONS_PENDING=1
    else
        echo "  ⚠ cron: $name — $cron_output"
        CRONS_PENDING=1
    fi
}
create_label() {
    local name="$1" color="$2" desc="$3"
    if gh label list --repo "$REPO" 2>/dev/null | grep -q "^$name"; then
        skip "label: $name"
    else
        gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" \
            && ok "label: $name"
    fi
}
# =============================================================================
# EXECUÇÃO
# =============================================================================
# -- Validações --
echo "[ Validações ]"
command -v gh       &>/dev/null || fail "GitHub CLI (gh) não instalado"
ok "gh disponível"
command -v jq       &>/dev/null || fail "jq não instalado"
ok "jq disponível"
command -v curl     &>/dev/null || fail "curl não instalado"
ok "curl disponível"
command -v openclaw &>/dev/null || fail "OpenClaw não instalado"
ok "openclaw disponível"
gh auth status &>/dev/null || fail "GitHub CLI não autenticado — execute: gh auth login"
ok "gh autenticado"
# Verificar se o token tem o scope 'project' necessário para GitHub Projects
GH_SCOPES=$(gh auth status 2>&1 | grep -i "token scopes\|scopes:" | head -1 || true)
if echo "$GH_SCOPES" | grep -q "project"; then
    ok "gh token: scope project presente"
else
    echo "  ⚠ gh token pode não ter scope 'project'"
    echo "    Se o board falhar, reautentique com:"
    echo "    gh auth login --scopes project"
fi
# Obter o login do usuário autenticado para usar como owner nos comandos project
GH_LOGIN=$(gh api user --jq .login 2>/dev/null || true)
[ -z "$GH_LOGIN" ] && fail "não foi possível obter o login do GitHub — verifique: gh auth status"
ok "gh login: $GH_LOGIN"
# -- Estrutura do projeto --
echo "[ Estrutura do projeto ]"
create_dir "$BASE_DIR"
create_dir "$BASE_DIR/memory"
create_dir "$BASE_DIR/memory/product"
create_dir "$BASE_DIR/memory/developer"
create_dir "$BASE_DIR/memory/reviewer"
create_dir "$BASE_DIR/memory/lead"
echo ""
# -- Arquivos de configuração do projeto --
echo "[ Configuração ]"
create_file "$BASE_DIR/PROJECT.md" "# PROJECT
## Nome
$PROJECT
## Repositório GitHub
$REPO
## Canal Discord
#$DISCORD_CHANNEL
## Status
active
## Criado em
$NOW"
create_file "$BASE_DIR/AGENTS.md" "# AGENTS FLOW
User → Product → Issue → Developer → PR → Reviewer → Merge → Lead Report
## Agentes
- ${PROJECT}-product   → interpreta demandas, cria Issues
- ${PROJECT}-developer → implementa código, abre PRs
- ${PROJECT}-reviewer  → revisa código, faz merge
- ${PROJECT}-lead      → supervisiona, reporta, coordena"
create_file "$BASE_DIR/GITHUB.md" "# GITHUB POLICY
Repositório: $REPO
## Branches
- feature/issue-XX
- fix/issue-XX
- refactor/issue-XX
## Commits (Conventional Commits)
- feat: | fix: | refactor: | chore:
## Labels obrigatórias
inbox · in_progress · review · blocked · done
agent:product · agent:developer · agent:reviewer"
create_file "$BASE_DIR/DISCORD.md" "# DISCORD POLICY
Canal: #$DISCORD_CHANNEL
## Fluxo
Usuário → Product interpreta → Issue criada → Developer implementa → Reviewer revisa → Lead reporta
## Nunca
- Criar tarefa só no Discord
- Tomar decisão técnica sem Issue
- Resolver conflito fora do GitHub"
create_file "$BASE_DIR/memory/MEMORY.md"    "# LONG TERM MEMORY — $PROJECT"
create_file "$BASE_DIR/memory/DAILY_LOG.md" "# DAILY LOG — $PROJECT"
echo ""
# -- Workspaces dos agentes (arquivos de identidade) --
echo "[ Workspaces dos agentes ]"
setup_agent_workspace "product"   "$PROJECT product"   "📋" "product manager"
setup_agent_workspace "developer" "$PROJECT developer" "💻" "software engineer"
setup_agent_workspace "reviewer"  "$PROJECT reviewer"  "🔍" "code reviewer"
setup_agent_workspace "lead"      "$PROJECT lead"      "🎯" "tech lead"
echo ""
# -- Registrar agentes no OpenClaw --
echo "[ Agentes OpenClaw ]"
create_agent "product"
create_agent "developer"
create_agent "reviewer"
create_agent "lead"
echo ""
# -- Crons --
echo "[ Crons ]"
create_cron "${PROJECT}-product-heartbeat"   "${PROJECT}-product"   "--every" "15m" \
    "Heartbeat: verifique mensagens em #$DISCORD_CHANNEL e Issues em $REPO. Siga o AGENTS.md."
create_cron "${PROJECT}-developer-heartbeat" "${PROJECT}-developer" "--every" "15m" \
    "Heartbeat: verifique Issues atribuídas em $REPO. Siga o AGENTS.md."
create_cron "${PROJECT}-reviewer-heartbeat"  "${PROJECT}-reviewer"  "--every" "15m" \
    "Heartbeat: verifique PRs abertas em $REPO. Siga o AGENTS.md."
create_cron "${PROJECT}-lead-standup"        "${PROJECT}-lead"      "--cron"  "0 23 * * *" \
    "Daily standup: execute a skill DAILY_STANDUP para $PROJECT. Poste no Discord #$DISCORD_CHANNEL."
echo ""
# -- Labels GitHub --
echo "[ Labels GitHub ]"
create_label "inbox"           "ededed" "Nova tarefa"
create_label "in_progress"     "0052cc" "Em desenvolvimento"
create_label "review"          "fbca04" "Em revisão"
create_label "blocked"         "d93f0b" "Bloqueado"
create_label "done"            "0e8a16" "Concluído"
create_label "agent:product"   "5319e7" "Responsável Product"
create_label "agent:developer" "1d76db" "Responsável Developer"
create_label "agent:reviewer"  "c2e0c6" "Responsável Reviewer"

# Labels de Tipo
create_label "feature"         "a2eeef" "Nova funcionalidade"
create_label "bug"             "d73a4a" "Bug ou erro"
create_label "refactor"        "e99695" "Refatoração de código"
create_label "chore"           "c5def5" "Tarefa rotineira"
create_label "spike"           "006b75" "Pequena pesquisa ou POC"

# Labels de Prioridade
create_label "p0:crítica"      "b60205" "Prioridade máxima"
create_label "p1:alta"         "d93f0b" "Prioridade alta"
create_label "p2:normal"       "0e8a16" "Prioridade normal"
create_label "p3:baixa"        "fbca04" "Prioridade baixa"
echo ""
# -- GitHub Project Board --
# Usa GraphQL diretamente — gh project CLI falha sem scope interativo
# Obter node_id do owner (user ou org) via REST
_board_owner_id() {
    local id
    # OWNER = dono do repo (org ou user), extraído de $REPO (ex: barba-software/quemresolve-backend)
    id=$(gh api "orgs/$OWNER" --jq .node_id 2>/dev/null) && echo "$id" && return
    gh api "users/$OWNER" --jq .node_id 2>/dev/null || true
}
# Buscar board existente por título via GraphQL
_board_find() {
    local owner_id="$1"
    local raw
    raw=$(gh api graphql -f query="
query {
  node(id: \"$owner_id\") {
    ... on User         { projectsV2(first:20) { nodes { id number title closed } } }
    ... on Organization { projectsV2(first:20) { nodes { id number title closed } } }
  }
}
" 2>/dev/null) || true
    echo "$raw" | jq -rc ".data.node.projectsV2.nodes[] | select(.title == \"$BOARD_NAME\")" 2>/dev/null | head -1 || true
}
_board_reopen() {
    local project_id="$1"
    gh api graphql -f query="
mutation {
  updateProjectV2(input: { projectId: \"$project_id\", closed: false }) {
    projectV2 { id closed }
  }
}
" 2>/dev/null || true
}
# Criar board via GraphQL
_board_create_gql() {
    local owner_id="$1"
    local raw
    raw=$(gh api graphql -f query="
mutation {
  createProjectV2(input: { ownerId: \"$owner_id\", title: \"$BOARD_NAME\" }) {
    projectV2 { id number title }
  }
}
" 2>/dev/null) || true
    echo "$raw" | jq -rc ".data.createProjectV2.projectV2" 2>/dev/null || true
}
# ✅ CORREÇÃO: Criar opção no campo Status via GraphQL
# Problema: API do GitHub exige campo 'description' em TODAS as opções
# Criar opção no campo Status via GraphQL
_board_add_status_option() {
    local project_id="$1" field_id="$2" opt="$3"
    
    # Verificar se já existe via arquivo temporário
    local _tmp_opts
    _tmp_opts=$(mktemp)
    gh api graphql -f query="
query {
  node(id: \"$project_id\") {
    ... on ProjectV2 {
      fields(first: 20) {
        nodes {
          ... on ProjectV2SingleSelectField { name options { id name } }
        }
      }
    }
  }
}
" 2>/dev/null > "$_tmp_opts" || true
    
    local exists
    exists=$(jq -r '.data.node.fields.nodes[] | select(.name == "Status") | .options[].name' "$_tmp_opts" 2>/dev/null | grep -x "$opt" || true)
    
    if [ -n "$exists" ]; then
        rm -f "$_tmp_opts"
        skip "coluna: $opt"
        return
    fi
    
    # Coletar opções existentes para passar junto com a nova
    # GitHub exige todas as opções na mutation updateProjectV2Field
    local existing_options_json
    existing_options_json=$(jq -c '[.data.node.fields.nodes[] | select(.name == "Status") | .options[] | {name: .name, color: "GRAY", description: ""}]' "$_tmp_opts" 2>/dev/null || echo "[]")
    rm -f "$_tmp_opts"
    
    # Montar array com as opções existentes + nova
    local all_options_json
    all_options_json=$(echo "$existing_options_json" | jq -c --arg name "$opt" '. + [{name: $name, color: "GRAY", description: ""}]')
    
    # ✅ CORREÇÃO: Criar JSON único com query + variables (NÃO usar -F + --input juntos)
    local _tmp_payload
    _tmp_payload=$(mktemp)
    cat > "$_tmp_payload" << EOF
{
  "query": "mutation UpdateField(\$fieldId: ID!, \$options: [ProjectV2SingleSelectFieldOptionInput!]!) { updateProjectV2Field(input: { fieldId: \$fieldId, singleSelectOptions: \$options }) { projectV2Field { ... on ProjectV2SingleSelectField { name options { name } } } } }",
  "variables": {
    "fieldId": "$field_id",
    "options": $all_options_json
  }
}
EOF
    
    local out exit_code
    out=$(gh api graphql --input "$_tmp_payload" 2>&1) && exit_code=0 || exit_code=$?
    rm -f "$_tmp_payload"
    
    if [ $exit_code -eq 0 ] && echo "$out" | jq -e ".data" &>/dev/null; then
        ok "coluna: $opt"
    else
        echo "  ⚠ coluna: $opt — $out"
    fi
}
echo "[ GitHub Project Board ]"
BOARD_NAME="$PROJECT Board"
OWNER_NODE_ID=$(_board_owner_id)
if [ -z "$OWNER_NODE_ID" ]; then
    echo "  ⚠ board: nao foi possivel obter node_id do owner $OWNER"
else
    # Buscar ou criar board
    BOARD_JSON=$(_board_find "$OWNER_NODE_ID")
    if [ -z "$BOARD_JSON" ]; then
        BOARD_JSON=$(_board_create_gql "$OWNER_NODE_ID")
        if [ -n "$BOARD_JSON" ]; then
            ok "board criado: $BOARD_NAME"
        else
            echo "  ⚠ board: falha ao criar via GraphQL — verifique scope do token (project)"
        fi
    else
        # Verificar se board está fechado — reabrir se necessário
        IS_CLOSED=$(echo "$BOARD_JSON" | jq -r '.closed // false')
        if [ "$IS_CLOSED" = "true" ]; then
            REOPEN_ID=$(echo "$BOARD_JSON" | jq -r '.id')
            _board_reopen "$REOPEN_ID" >/dev/null
            ok "board reaberto: $BOARD_NAME"
        else
            skip "board: $BOARD_NAME"
        fi
    fi
    if [ -n "$BOARD_JSON" ]; then
        BOARD_NODE_ID=$(echo "$BOARD_JSON" | jq -r '.id // empty')
        BOARD_NUMBER=$(echo "$BOARD_JSON" | jq -r '.number // empty')
        # Buscar campo Status — arquivo temporário para evitar truncamento de variável bash
        _TMP_FIELDS=$(mktemp)
        gh api graphql -f query="
query {
  node(id: \"$BOARD_NODE_ID\") {
    ... on ProjectV2 {
      fields(first: 20) {
        nodes {
          ... on ProjectV2SingleSelectField { id name options { id name } }
          ... on ProjectV2Field { id name }
        }
      }
    }
  }
}
" 2>/dev/null > "$_TMP_FIELDS" || true
        STATUS_FIELD_NODE_ID=$(jq -r '.data.node.fields.nodes[] | select(.name == "Status") | .id' "$_TMP_FIELDS" 2>/dev/null || true)
        rm -f "$_TMP_FIELDS"
        if [ -n "$STATUS_FIELD_NODE_ID" ] && [ "$STATUS_FIELD_NODE_ID" != "null" ]; then
            skip "campo Status (id: $STATUS_FIELD_NODE_ID)"
        else
            echo "  ⚠ campo Status nao encontrado no board"
        fi
        if [ -n "$BOARD_NODE_ID" ] && [ -n "$STATUS_FIELD_NODE_ID" ]; then
            for col in Inbox "In Progress" Review Blocked Done; do
                _board_add_status_option "$BOARD_NODE_ID" "$STATUS_FIELD_NODE_ID" "$col"
            done
        fi
    fi
fi
echo ""
# -- Registry global --
echo "[ Registry ]"
[ -f "$REGISTRY" ] || echo "[]" > "$REGISTRY"
if ! jq -e ".[] | select(.project == \"$PROJECT\")" "$REGISTRY" &>/dev/null; then
    tmp=$(mktemp)
    jq ". += [{\"project\":\"$PROJECT\",\"repo\":\"$REPO\",\"discord\":\"$DISCORD_CHANNEL\",\"created_at\":\"$NOW\"}]" \
        "$REGISTRY" > "$tmp" && mv "$tmp" "$REGISTRY"
    ok "registrado em registry.json"
else
    skip "projeto já no registry.json"
fi
echo ""
# -- Crons pendentes --
if [ "$CRONS_PENDING" = "1" ]; then
    echo "[ ⚠ Crons pendentes ]"
    echo "  O gateway não estava conectado durante a criação dos crons."
    echo "  Corrija o token e recrie com:"
    echo "    openclaw doctor  ← diagnóstico"
    echo "    ./provision.sh $PROJECT $REPO $DISCORD_CHANNEL  ← idempotente, recria só os crons faltantes"
    echo ""
fi
echo "═══════════════════════════════════════════════"
echo "✅ Provisionamento completo: $PROJECT"
echo "   Repo:    $REPO"
echo "   Discord: #$DISCORD_CHANNEL"
echo ""
echo "Agentes criados e configurados:"
echo "  ${PROJECT}-product   📋 Product Manager"
echo "  ${PROJECT}-developer 💻 Software Engineer"
echo "  ${PROJECT}-reviewer  🔍 Code Reviewer"
echo "  ${PROJECT}-lead      🎯 Tech Lead"
echo ""
echo "Próximo passo:"
echo "  $HOME/.openclaw/workspace/scripts/health_check.sh $PROJECT"
echo "═══════════════════════════════════════════════"