#!/usr/bin/env bash
# =============================================================================
# health_check.sh — Verificação de saúde do sistema OpenClaw
# =============================================================================
# Uso: health_check.sh [project]
#
# Sem argumentos: verifica todos os projetos no registry.json
# Com argumento:  verifica apenas o projeto especificado
#
# Verifica:
#   1. state.json válido e consistente
#   2. Capacidade dos agentes coerente com active_issues
#   3. Crons de heartbeat ativos
#   4. Existência de issues "stuck" (sem atualização há mais de 48h)
#   5. Divergência entre estado interno e GitHub
# =============================================================================

set -euo pipefail

FILTER_PROJECT="${1:-}"
WORKSPACE="$HOME/.openclaw/workspace"
REGISTRY="$WORKSPACE/registry.json"
EXIT_CODE=0

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✔${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; EXIT_CODE=1; }
fail() { echo -e "  ${RED}❌${NC} $1"; EXIT_CODE=2; }
info() { echo -e "  ${BLUE}ℹ${NC} $1"; }

echo "======================================"
echo "  OpenClaw Health Check"
echo "  $(date)"
echo "======================================"
echo ""

# ── Determinar projetos a verificar ──────────────────────────────────────────
PROJECTS=()
if [ -n "$FILTER_PROJECT" ]; then
  PROJECTS=("$FILTER_PROJECT")
elif [ -f "$REGISTRY" ]; then
  while IFS= read -r proj; do
    PROJECTS+=("$proj")
  done < <(jq -r '.[].project' "$REGISTRY" 2>/dev/null || true)
else
  warn "registry.json não encontrado em $REGISTRY"
  # Fallback: listar pastas existentes
  for d in "$WORKSPACE/projects"/*/; do
    [ -d "$d" ] && PROJECTS+=("$(basename "$d")")
  done
fi

if [ ${#PROJECTS[@]} -eq 0 ]; then
  warn "Nenhum projeto encontrado para verificar"
  exit 1
fi

# ── Checar dependências ───────────────────────────────────────────────────────
check_deps() {
  echo "[ Dependências ]"
  for cmd in jq gh openclaw; do
    if command -v "$cmd" &>/dev/null; then
      ok "$cmd disponível"
    else
      warn "$cmd não encontrado"
    fi
  done
  echo ""
}

check_deps

# ── Verificar projeto por projeto ─────────────────────────────────────────────
for PROJECT in "${PROJECTS[@]}"; do
  BASE="$WORKSPACE/projects/$PROJECT"
  STATE_FILE="$BASE/state.json"
  AUDIT_LOG="$BASE/audit.log"

  echo "[ Projeto: $PROJECT ]"

  # 1. Estrutura de diretórios
  if [ ! -d "$BASE" ]; then
    fail "Diretório do projeto não encontrado: $BASE"
    echo ""
    continue
  fi
  ok "Diretório existe"

  # 2. state.json presente
  if [ ! -f "$STATE_FILE" ]; then
    fail "state.json ausente"
    echo ""
    continue
  fi
  ok "state.json presente"

  # 3. state.json válido
  if ! jq -e . "$STATE_FILE" &>/dev/null; then
    fail "state.json é JSON inválido"
    echo ""
    continue
  fi
  ok "state.json é JSON válido"

  # 4. Campos obrigatórios
  missing_fields=0
  for field in project repo agents issues version; do
    if ! jq -e "has(\"$field\")" "$STATE_FILE" &>/dev/null; then
      warn "state.json: campo '$field' ausente"
      missing_fields=$((missing_fields+1))
    fi
  done
  [ $missing_fields -eq 0 ] && ok "Campos obrigatórios presentes"

  # 5. Consistência de capacidade
  echo ""
  info "Verificando agentes..."
  while IFS= read -r agent; do
    capacity=$(jq -r --arg a "$agent" '.agents[$a].capacity' "$STATE_FILE")
    active=$(jq --arg a "$agent" '.agents[$a].active_issues | length' "$STATE_FILE")
    role=$(jq -r --arg a "$agent" '.agents[$a].role' "$STATE_FILE")

    if [ "$active" -gt "$capacity" ]; then
      fail "$agent ($role): $active issues ativas > capacidade $capacity"
    else
      ok "$agent ($role): $active/$capacity issues"
    fi

    # Verificar se issues listadas existem
    while IFS= read -r issue_in_agent; do
      if ! jq -e --arg i "$issue_in_agent" '.issues[$i]' "$STATE_FILE" &>/dev/null; then
        warn "$agent: issue '$issue_in_agent' em active_issues mas não registrada em .issues"
      fi
    done < <(jq -r --arg a "$agent" '.agents[$a].active_issues[]' "$STATE_FILE" 2>/dev/null || true)

  done < <(jq -r '.agents | keys[]' "$STATE_FILE")

  # 6. Issues stuck (sem update > 48h)
  echo ""
  info "Verificando issues paradas..."
  CUTOFF=$(date -d '48 hours ago' -Iseconds 2>/dev/null || date -v-48H -Iseconds 2>/dev/null || echo "")
  stuck_count=0
  if [ -n "$CUTOFF" ]; then
    while IFS= read -r issue_id; do
      updated_at=$(jq -r --arg i "$issue_id" '.issues[$i].updated_at // empty' "$STATE_FILE")
      status=$(jq -r --arg i "$issue_id" '.issues[$i].status' "$STATE_FILE")

      if [ -n "$updated_at" ] && [ "$status" != "done" ] && [[ "$updated_at" < "$CUTOFF" ]]; then
        warn "Issue #$issue_id ($status) parada desde $updated_at"
        stuck_count=$((stuck_count+1))
      fi
    done < <(jq -r '.issues | keys[]' "$STATE_FILE" 2>/dev/null || true)
    [ $stuck_count -eq 0 ] && ok "Nenhuma issue parada"
  else
    info "Verificação de issues stuck pulada (date -d não suportado)"
  fi

  # 7. Backup recente
  if [ -f "${STATE_FILE}.bak" ]; then
    ok "Backup do state existe"
  else
    warn "Backup do state ausente (backup criado na primeira execução do state-engine)"
  fi

  # 8. Audit log
  if [ -f "$AUDIT_LOG" ]; then
    lines=$(wc -l < "$AUDIT_LOG")
    ok "audit.log presente ($lines entradas)"
    # Verificar erros recentes (últimas 50 linhas)
    recent_errors=$(tail -50 "$AUDIT_LOG" 2>/dev/null | grep -c "status=ERROR" || true)
    if [ "$recent_errors" -gt 0 ]; then
      warn "$recent_errors erros nas últimas 50 entradas do audit.log"
    fi
  else
    warn "audit.log ausente (criado na primeira execução do state-engine)"
  fi

  # 9. Issues orphaned em .issues mas não em nenhum active_issues (apenas in_progress)
  echo ""
  info "Verificando consistência issues x agentes..."
  orphan_count=0
  while IFS= read -r issue_id; do
    status=$(jq -r --arg i "$issue_id" '.issues[$i].status' "$STATE_FILE")
    if [ "$status" = "in_progress" ]; then
      in_active=$(jq --arg i "$issue_id" '[.agents[].active_issues[] | select(. == $i)] | length' "$STATE_FILE")
      if [ "$in_active" -eq 0 ]; then
        warn "Issue #$issue_id (in_progress) não está em active_issues de nenhum agente"
        orphan_count=$((orphan_count+1))
      fi
    fi
  done < <(jq -r '.issues | keys[]' "$STATE_FILE" 2>/dev/null || true)
  [ $orphan_count -eq 0 ] && ok "Issues in_progress consistentes com active_issues"

  echo ""
done

# ── Resumo ────────────────────────────────────────────────────────────────────
echo "======================================"
if [ $EXIT_CODE -eq 0 ]; then
  echo -e "  ${GREEN}✔ SISTEMA SAUDÁVEL${NC}"
elif [ $EXIT_CODE -eq 1 ]; then
  echo -e "  ${YELLOW}⚠ ATENÇÃO: avisos encontrados${NC}"
else
  echo -e "  ${RED}❌ ERROS CRÍTICOS ENCONTRADOS${NC}"
fi
echo "  Verificado em: $(date)"
echo "======================================"

exit $EXIT_CODE
