---
name: "review_pr"
description: "Realiza revisões de código automatizadas seguindo checklists de qualidade."
---

# SKILL: REVIEW_PR

**Responsável:** Reviewer Agent
**Permissão:** role=reviewer
**Trigger:** issue em estado review (pr_created disparado)

---

## Protocolo de Revisão

### 0. Anunciar início na thread review

```bash
REVIEW_THREAD=$(jq -r '.discord_review_thread_id // empty' ~/.openclaw/workspace/projects/{project}/state.json)
openclaw message send \
  --channel discord \
  --target "thread:$REVIEW_THREAD" \
  --message "👀 Iniciando revisão do PR #{numero_pr} — Issue #{issue}"
```

### 1. Validar Contexto (Obrigatório)

Antes de checar o código, verifique se o Developer preencheu corretamente o corpo do PR:

- [ ] O campo "O que foi resolvido" está claro?
- [ ] Os "Critérios de Aceite" foram marcados?
- [ ] Existe uma seção de "Testes"?

**Se a descrição estiver vaga ou incompleta:** não siga com a revisão. Solicite os detalhes no PR e mova para `blocked` imediatamente.

### 2. Listar PRs aguardando revisão (priorizar os mais antigos)

```bash
gh pr list --repo {repo} --label review --state open --json number,title,createdAt --jq 'sort_by(.createdAt) | .[].number'
```

### 3. Fazer checkout do PR

```bash
gh pr checkout {numero_pr} --repo {repo}
```

### 3b. Identificar a Issue vinculada

O `state_engine` precisa do número da **Issue** (ex: #15), não do PR. Procure no corpo do PR por "Closes #XX" ou "Fixes #XX":

```bash
ISSUE_NUM=$(gh pr view {numero_pr} --repo {repo} --json body --jq '.body | grep -oE "Closes #[0-9]+" | cut -d# -f2')
echo "Issue vinculada: $ISSUE_NUM"
```

### 3. Checklist de Revisão

#### Funcionalidade

- [ ] Implementação cobre todos os critérios de aceite da Issue
- [ ] Edge cases tratados
- [ ] Sem regressões óbvias

#### Qualidade

- [ ] Código legível sem necessidade de comentários explicativos
- [ ] Funções com responsabilidade única
- [ ] Sem código morto ou comentado

#### Testes

- [ ] Testes unitários para lógica de negócio
- [ ] Cenários de erro cobertos
- [ ] Testes passando localmente: `{test_command}`

#### Segurança

- [ ] Sem segredos hardcoded
- [ ] Inputs validados
- [ ] Sem SQL injection / XSS se aplicável

#### Performance

- [ ] Sem N+1 queries
- [ ] Operações custosas com cache quando faz sentido

### 4a. Validação Técnica (Aprovação)

Se o código estiver de acordo com todos os requisitos instrumentados, registre a validação:

```bash
gh pr review {numero_pr} --repo {repo} --comment \
  --body "✅ Validado tecnicamente por {{NAME}}. Todos os critérios de aceite foram atendidos e os testes passaram localmente. @User, o PR está pronto para sua revisão final e merge."
```

Disparar transição de estado para `approved` e anunciar na thread review:

```bash
bash $HOME/.openclaw/workspace/scripts/state_engine.sh {project} {repo} $ISSUE_NUM approved

REVIEW_THREAD=$(jq -r '.discord_review_thread_id // empty' ~/.openclaw/workspace/projects/{project}/state.json)
openclaw message send \
  --channel discord \
  --target "thread:$REVIEW_THREAD" \
  --message "✅ PR #{numero_pr} validada tecnicamente — aguardando merge do usuário"
```

### 4b. Solicitação de mudanças

```bash
gh pr review {numero_pr} --repo {repo} --request-changes \
  --body "🔄 Mudanças necessárias:\n- Item 1\n- Item 2"
```

Bloquear a issue no State Engine e anunciar na thread review:

```bash
bash $HOME/.openclaw/workspace/scripts/state_engine.sh {project} {repo} $ISSUE_NUM blocked "PR precisa de ajustes: {resumo_das_mudanças}"

REVIEW_THREAD=$(jq -r '.discord_review_thread_id // empty' ~/.openclaw/workspace/projects/{project}/state.json)
openclaw message send \
  --channel discord \
  --target "thread:$REVIEW_THREAD" \
  --message "🔁 PR #{numero_pr} precisa de ajustes: {resumo}"
```

---

## Observação sobre o Merge

O Reviewer Agent **NUNCA** realiza o merge. Após a validação técnica (estado `approved`), o ciclo de vida da issue será encerrado pelo sistema assim que o usuário realizar o merge manual no GitHub (detectado via reconciliação de estado).

---

## Regras Invioláveis

- ❌ Nunca realizar merge de Pull Requests
- ❌ Nunca discutir código fora do contexto do PR
- ❌ Nunca fechar Issue manualmente
