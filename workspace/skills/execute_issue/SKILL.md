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

### 1. Encontrar Issues Atribuídas

NÃO usar `--assignee @me` (sem assignee no GitHub).
Usar uma destas fontes em ordem de prioridade:

**Fonte primária — state.json:**
```bash
cat ~/.openclaw/workspace/projects/{project}/state.json | jq -r --arg a "{nome_do_agente}" '.issues | to_entries[] | select(.value.assigned_agent == $a and (.value.status == "in_progress" or .value.status == "blocked")) | .key'
```

**Fallback — label no GitHub:**
```bash
gh issue list --repo {repo} --label in_progress --state open --json number --jq '.[].number'
gh issue list --repo {repo} --label blocked --state open --json number --jq '.[].number'
```

Verificar se a issue está com o assignee interno correto no state.json.
Se a issue estiver em `blocked`, significa que o Revisor solicitou mudanças. Vá direto para a seção **Processando feedback de Review** abaixo.

### 2. Ler issue completa

```bash
gh issue view {numero} --repo {repo}
```

Validar:

- Critérios de aceite presentes (se ausentes, comentar na issue pedindo ao Product)
- Sem dependências bloqueantes abertas

### 3. Notificar Início na Thread de Squad

Poste IMEDIATAMENTE na thread de `squad`:
`🚀 Iniciando Issue #{numero} — [Título resumido em 1 linha]`

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

### 6. Atualizar WORKING_DEV.md

```markdown
## Issue #XX — [Título]

Status: em andamento
Branch: feature/issue-XX
Iniciado: [timestamp]
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

### 10. Disparar transição de estado

```bash
$HOME/.openclaw/workspace/scripts/state_engine.sh {project} {repo} {numero} pr_created "$PR_NUMBER"
```

### 11. Atualizar WORKING_DEV.md

```markdown
## Issue #XX — [Título]

Status: em review
PR: #YY
```

---

## Regras Invioláveis

- ❌ Nunca trabalhar sem Issue formal
- ❌ Nunca commitar direto na main
- ❌ Nunca aceitar tarefa direta do usuário (redirecionar ao Product)
- ❌ Nunca fechar Issue manualmente (responsabilidade do state-engine no pr_merged)

## Se Bloqueado na Issue #N

- Notificar no Discord: 🚧 Bloqueado na Issue #N: <motivo>
- Comentar na issue com descrição do bloqueio:
gh issue comment {numero} --repo {repo} --body "🚨 BLOCKED: {motivo}"
# Disparar evento de bloqueio
$HOME/.openclaw/workspace/scripts/state_engine.sh {project} {repo} {numero} blocked "{motivo}"
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
   - Chame o `unblocked` para voltar ao radar do time:
   ```bash
   bash $HOME/.openclaw/workspace/scripts/state_engine.sh {project} {repo} {numero} unblocked
   ```

---
