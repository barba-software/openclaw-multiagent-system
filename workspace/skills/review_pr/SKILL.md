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

### 4a. Aprovação

```bash
gh pr review {numero_pr} --repo {repo} --approve \
  --body "✅ Aprovado. Critérios de aceite atendidos."
```

Disparar transição e notificar:

```bash
$HOME/.openclaw/workspace/scripts/state_engine.sh {project} {repo} {issue_numero} pr_approved
```
- A skill ou script de aprovação deve postar no Discord: `✅ PR #{numero_pr} aprovada`

### 4b. Solicitação de mudanças

```bash
gh pr review {numero_pr} --repo {repo} --request-changes \
  --body "🔄 Mudanças necessárias:\n- Item 1\n- Item 2"
```

Bloquear a issue no State Engine:

```bash
$HOME/.openclaw/workspace/scripts/state_engine.sh {project} {repo} {issue_numero} blocked "PR precisa de ajustes: {resumo_das_mudanças}"
```

- Notificar no Discord: `🔁 PR #{numero_pr} precisa de ajustes: <resumo>`

### 5. Merge (após aprovação)

```bash
gh pr merge {numero_pr} --repo {repo} --squash --delete-branch
```

### 6. Disparar conclusão

```bash
$HOME/.openclaw/workspace/scripts/state_engine.sh {project} {repo} {issue_numero} pr_merged
```

- Notificar no Discord: `✅ PR #{numero_pr} mergeada — Issue #{issue_numero} concluída: <url>`

O state-engine se encarrega de: liberar capacidade do developer, atualizar estado para done, fechar a Issue e mover o card.

---

## Regras Invioláveis

- ❌ Nunca mergear sem aprovação explícita
- ❌ Nunca mergear se testes estão falhando
- ❌ Nunca discutir código fora do contexto do PR
- ❌ Nunca fechar Issue manualmente
