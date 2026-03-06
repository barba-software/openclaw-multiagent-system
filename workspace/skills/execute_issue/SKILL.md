---
name: "execute_issue"
description: "Gerencia o ciclo de desenvolvimento: branch, commits e Pull Request."
---

# SKILL: EXECUTE_ISSUE

**Responsável:** Developer Agent
**Permissão:** role=developer
**Trigger:** issue atribuída via auto_assign

---

## Protocolo de Execução

### 0. Carregar contexto persistente (sempre primeiro)

```bash
WORKING="$HOME/.openclaw/workspace/projects/{project}/agents/developer/WORKING.md"
LESSONS="$HOME/.openclaw/workspace/projects/{project}/agents/developer/LESSONS.md"
cat "$WORKING"
cat "$LESSONS" 2>/dev/null || true
```

Se `STATUS: em andamento` no WORKING.md: a issue foi interrompida no ciclo anterior. **Pule direto para a próxima etapa pendente** (indicada em `STEP:`) em vez de recomeçar do zero.  
Se `STATUS: idle`: execute normalmente a partir do passo 1.

### 1. Encontrar Issues Atribuídas

NÃO usar `--assignee @me` (sem assignee no GitHub).
Usar uma destas fontes em ordem de prioridade:

**Fonte primária — state.json** (use `developer-1` como sua chave interna):

```bash
cat ~/.openclaw/workspace/projects/{project}/state.json | jq -r '.issues | to_entries[] | select(.value.assigned_agent == "developer-1" and (.value.status == "in_progress" or .value.status == "blocked")) | .key'
```

**Fallback — label no GitHub:**

```bash
gh issue list --repo {repo} --label in_progress --state open --json number --jq '.[].number'
gh issue list --repo {repo} --label blocked --state open --json number --jq '.[].number'
```

Verificar se a issue está com o assignee interno correto no state.json.
Se a issue estiver em `blocked`, significa que o Revisor solicitou mudanças. Vá direto para a seção **Processando feedback de Review** abaixo.

```bash
# Checkpoint — issue encontrada
WORKING="$HOME/.openclaw/workspace/projects/{project}/agents/developer/WORKING.md"
sed -i '' 's/^STATUS: .*/STATUS: em andamento/' "$WORKING"
sed -i '' 's/^ISSUE: .*/ISSUE: #{numero}/' "$WORKING"
sed -i '' 's/^STEP: .*/STEP: 1 — issue encontrada/' "$WORKING"
sed -i '' "s/^UPDATED: .*/UPDATED: $(date -Iseconds)/" "$WORKING"
```

### 2. Ler issue completa

```bash
gh issue view {numero} --repo {repo}
```

Validar:

- Critérios de aceite presentes (se ausentes, comentar na issue pedindo ao Product)
- Sem dependências bloqueantes abertas

### 3. Notificar Início na Thread de Dev

Poste IMEDIATAMENTE via `openclaw message send` antes de qualquer trabalho:

```bash
DEV_THREAD=$(jq -r '.discord.threads.dev // empty' ~/.openclaw/workspace/projects/{project}/state.json)
openclaw message send \
  --channel discord \
  --target "thread:$DEV_THREAD" \
  --message "🚀 Iniciando Issue #{numero} — [Título resumido em 1 linha]"

# Checkpoint — anúncio feito
sed -i '' 's/^STEP: .*/STEP: 3 — anúnciado no Discord/' "$WORKING"
sed -i '' 's/^NEXT: .*/NEXT: criar branch/' "$WORKING"
sed -i '' "s/^UPDATED: .*/UPDATED: $(date -Iseconds)/" "$WORKING"
```

### 5. Navegar para o Workspace e Criar branch

Todo o trabalho deve ocorrer estritamente dentro do repositório clonado do projeto:

```bash
cd ~/.openclaw/workspace/projects/{project}/repo
```

```bash
git checkout main && git pull
git checkout -b feature/issue-{numero}
# Para bugs: fix/issue-{numero}
# Para refatoração: refactor/issue-{numero}
```

```bash
# Checkpoint — branch criada
sed -i '' 's/^BRANCH: .*/BRANCH: feature\/issue-{numero}/' "$WORKING"
sed -i '' 's/^STEP: .*/STEP: 5 — branch criada/' "$WORKING"
sed -i '' 's/^NEXT: .*/NEXT: implementar/' "$WORKING"
sed -i '' "s/^UPDATED: .*/UPDATED: $(date -Iseconds)/" "$WORKING"
```

### 6. Checkpoint de progresso

```bash
# Registrar início de implementação
sed -i '' 's/^STEP: .*/STEP: 6 — implementando/' "$WORKING"
sed -i '' 's/^NEXT: .*/NEXT: commit e PR/' "$WORKING"
sed -i '' "s/^UPDATED: .*/UPDATED: $(date -Iseconds)/" "$WORKING"
```

### 7. Implementar

- Código claro > código inteligente
- Cobrir os critérios de aceite um a um
- Adicionar testes para cada critério

### 8. Commit (Conventional Commits obrigatório)

Obrigatório utilizar a identidade do agente para o commit:

```bash
git config user.name "alfred-ai-developer"
git config user.email "alfred-ai-developer@barbasoftware.com.br"
```

```bash
git add .
git commit -m "feat: implementa #{numero} — [descrição curta]"
```

```bash
# Checkpoint — commit realizado
sed -i '' 's/^STEP: .*/STEP: 8 — commit realizado/' "$WORKING"
sed -i '' 's/^NEXT: .*/NEXT: abrir PR/' "$WORKING"
sed -i '' "s/^UPDATED: .*/UPDATED: $(date -Iseconds)/" "$WORKING"
```

### 9. Abrir Pull Request

Você DEVE preencher o corpo do PR com informações pertinentes sobre o que foi resolvido ou implementado, detalhando a lógica e o contexto da solução para o revisor.

```bash
PR_URL=$(gh pr create \
  --repo {repo} \
  --title "feat: #{numero} — {título da issue}" \
  --body "Closes #{numero}\n\n## O que foi resolvido\n[Descreva detalhadamente a lógica implementada, qual problema foi solucionado e como os critérios de aceite foram atendidos]\n\n## Mudanças\n- [Lista das exclusões/adições mais impactantes]\n\n## Testes\n- [ ] [Liste como testar/quais testes foram feitos]" \
  --assignee @me)
PR_NUMBER=$(echo $PR_URL | grep -oE "[0-9]+$")
```

```bash
# Checkpoint — PR aberta
sed -i '' 's/^STEP: .*/STEP: 9 — PR aberta/' "$WORKING"
sed -i '' 's/^NEXT: .*/NEXT: disparar state engine/' "$WORKING"
sed -i '' "s/^UPDATED: .*/UPDATED: $(date -Iseconds)/" "$WORKING"
```

### 10. Disparar transição de estado e anunciar na Thread de Dev

```bash
bash $HOME/.openclaw/workspace/scripts/state_engine.sh {project} {repo} {numero} pr_created "$PR_NUMBER"

# Anunciar PR aberta na thread dev
DEV_THREAD=$(jq -r '.discord.threads.dev // empty' ~/.openclaw/workspace/projects/{project}/state.json)
openclaw message send \
  --channel discord \
  --target "thread:$DEV_THREAD" \
  --message "✅ PR #$PR_NUMBER aberta para Issue #{numero} — aguardando revisão"
```

### 11. Resetar WORKING.md (issue concluída neste ciclo)

```bash
# Limpar estado — próximo ciclo começa sem contexto antigo
sed -i '' 's/^STATUS: .*/STATUS: idle/' "$WORKING"
sed -i '' 's/^ISSUE: .*/ISSUE: —/' "$WORKING"
sed -i '' 's/^STEP: .*/STEP: 0/' "$WORKING"
sed -i '' 's/^NEXT: .*/NEXT: aguardando issues/' "$WORKING"
sed -i '' 's/^BRANCH: .*/BRANCH: —/' "$WORKING"
sed -i '' "s/^UPDATED: .*/UPDATED: $(date -Iseconds)/" "$WORKING"
```

---

## Regras Invioláveis

- ❌ Nunca trabalhar sem Issue formal
- ❌ Nunca commitar direto na main
- ❌ Nunca aceitar tarefa direta do usuário (redirecionar ao Product)
- ❌ Nunca fechar Issue manualmente (responsabilidade do state-engine no pr_merged)

## Se Bloqueado na Issue #N

```bash
# Comentar na issue e disparar evento de bloqueio
gh issue comment {numero} --repo {repo} --body "🚨 BLOCKED: {motivo}"
bash $HOME/.openclaw/workspace/scripts/state_engine.sh {project} {repo} {numero} blocked "{motivo}"

# Anunciar bloqueio na thread dev
DEV_THREAD=$(jq -r '.discord.threads.dev // empty' ~/.openclaw/workspace/projects/{project}/state.json)
openclaw message send \
  --channel discord \
  --target "thread:$DEV_THREAD" \
  --message "🚨 Bloqueado na Issue #{numero} — {motivo}"

# Checkpoint — bloqueado
sed -i '' 's/^STATUS: .*/STATUS: bloqueado/' "$WORKING"
sed -i '' 's/^STEP: .*/STEP: bloqueado/' "$WORKING"
sed -i '' 's/^NEXT: .*/NEXT: {motivo}/' "$WORKING"
sed -i '' "s/^UPDATED: .*/UPDATED: $(date -Iseconds)/" "$WORKING"

# Registrar lição aprendida se o bloqueio tiver causa técnica
# Invocar SELF_REFLECT: ~/.openclaw/workspace/skills/self_reflect/SKILL.md
```

## Processando feedback de Review

Se o revisor solicitar mudanças (estado `blocked` vindo de `review`):

1. Leia os comentários no Pull Request:
   ```bash
   gh pr view --repo {repo} --web # Ou via CLI
   ```
2. Realize os ajustes necessários localmente na **mesma branch**.
3. Faça o commit e push:
   ```bash
   git add .
   git commit -m "fix: aplica ajustes solicitados no review"
   git push origin feature/issue-{numero}
   ```
4. Sinalize a correção e peça nova revisão:
   - Comente no PR: `Ajustes realizados. Prontos para nova revisão.`
   - Chame o `unblocked` para voltar ao radar do time e anuncie na thread dev:

   ```bash
   bash $HOME/.openclaw/workspace/scripts/state_engine.sh {project} {repo} {numero} unblocked

   DEV_THREAD=$(jq -r '.discord.threads.dev // empty' ~/.openclaw/workspace/projects/{project}/state.json)
   openclaw message send \
     --channel discord \
     --target "thread:$DEV_THREAD" \
     --message "🔄 Processando ajustes na Issue #{numero} — ajustes aplicados, retornando para revisão"
   ```

---
