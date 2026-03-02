---
name: "create_product_issue"
description: "Cria issues estruturadas no GitHub a partir de demandas do usuário."
---

# SKILL: CREATE_PRODUCT_ISSUE

**Responsável:** Product Agent
**Permissão:** role=product
**Trigger:** nova demanda do usuário via Discord

---

## Protocolo

### 1. Interpretar a demanda

Analisar a mensagem e identificar:

- **Tipo:** feature | bug | refactor | chore | spike
- **Prioridade:** p0:crítica | p1:alta | p2:normal | p3:baixa
- **Estimativa:** S (< 2h) | M (< 1 dia) | L (< 3 dias) | XL (sprint inteira)
- **Risco:** avaliar via RISK_ANALYSIS antes de criar a issue

### 2. Criar Issue formatada

```bash
gh issue create \
  --repo {repo} \
  --title "{tipo}: {título claro e objetivo}" \
  --body "{corpo abaixo}" \
  --label "{tipo},{prioridade}" \
  --project "{project} Board"
```

**Corpo obrigatório:**

```markdown
## Contexto

Por que essa issue existe? Qual situação levou a essa demanda?

## Problema / Objetivo

Qual dor resolve? Ou qual valor agrega?

## Hipótese

O que acreditamos que vai resolver? Por quê?

## Critérios de Aceite

- [ ] Critério 1 (verificável, binário)
- [ ] Critério 2
- [ ] Critério N

## Impacto Esperado

Qual métrica ou experiência muda após a entrega?

## Estimativa

Tamanho: {S|M|L|XL}
Risco: {baixo|médio|alto}

## Notas Técnicas

(opcional) contexto técnico relevante para o developer
```

### 3. Aplicar AUTO_LABEL automaticamente

Ver skill AUTO_LABEL.

### 4. Criar Issue e despachar com um único comando

Em vez de criar a Issue e chamar o state-engine separadamente, usar o script integrado:

```bash
bash $HOME/.openclaw/workspace/scripts/create_and_dispatch.sh \
  {project} \
  {repo} \
  "{título da issue}" \
  "{corpo completo em markdown}" \
  "{label1,label2}"
```

O script faz tudo automaticamente:
- Verifica duplicatas
- Cria a Issue no GitHub
- Dispara `state-engine issue_created` → `auto_assign`
- Aplica label `in_progress`
- Retorna o número e URL da Issue

O output do script já contém a mensagem pronta para postar no Discord. Se ele não for invocado como script e você fizer de outra forma, lembre de disparar explicitamente:
`bash $HOME/.openclaw/workspace/scripts/state_engine.sh {project} {repo} {N} issue_created`

### 5. Confirmar criação no Discord

Usar o output do script (última linha):
```
✅ Issue #{numero} criada: {url}
```

### 6. Atualizar WORKING_PRODUCT.md

```markdown
## Issue #{numero} — {título}

Status: inbox
Criada: {timestamp}
Tipo: {feature|bug|refactor|chore}
```

---

## Regras Invioláveis

- ❌ Nunca criar issue vaga ou sem critérios de aceite
- ❌ Nunca iniciar sem interpretar a demanda completa
- ❌ Nunca criar issue duplicada (verificar backlog antes)
- ❌ Nunca omitir o `create_and_dispatch.sh` (encapsula issue_created + auto_assign)
- ❌ Nunca criar Issue com `gh issue create` direto sem passar pelo create_and_dispatch.sh

## Verificar duplicata antes de criar

```bash
gh issue list --repo {repo} --state all --search "{termos-chave}" \
  --json number,title,state
```
