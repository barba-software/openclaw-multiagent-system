---
name: "block_detection"
description: "Detecta issues e PRs que estão estagnados ou bloqueados."
---

# SKILL: BLOCK_DETECTION

**Responsável:** Developer (auto-reporte) | Reviewer (detecção em review) | Lead (monitoramento)
**Trigger:** heartbeat ou detecção manual

---

## Detecção Automática (Lead / Heartbeat)

### 1. Issues com label blocked

```bash
gh issue list --repo {repo} --state open --label "blocked" \
  --json number,title,assignees,updatedAt,labels
```

### 2. Issues sem atualização há mais de 24h (in_progress)

```bash
# Verificar no state.json
cat $HOME/.openclaw/workspace/projects/{project}/state.json | jq '
  .issues | to_entries
  | map(select(.value.status == "in_progress"))
  | map(select(.value.updated_at < (now - 86400 | todate)))
  | map({issue: .key, status: .value.status, agent: .value.assigned_agent, since: .value.updated_at})
'
```

### 3. PRs em review há mais de 48h

```bash
gh pr list --repo {repo} --state open \
  --json number,title,createdAt,reviewDecision \
  --jq '[.[] | select(.reviewDecision != "APPROVED")]'
```

---

## Protocolo ao Detectar Bloqueio

### Se Developer detectar bloqueio (auto-reporte):

```bash
# 1. Comentar na issue com motivo detalhado
gh issue comment {numero} --repo {repo} \
  --body "🚨 BLOCKED\n\n**Motivo:** {motivo}\n**Preciso de:** {o que desbloqueia}\n**Estimativa para desbloquear:** {tempo}"

# 2. Aplicar label
gh issue edit {numero} --repo {repo} --add-label "blocked" --remove-label "in_progress"

# 3. Disparar evento no state-engine
$HOME/.openclaw/workspace/scripts/state_engine.sh {project} {repo} {numero} blocked "{motivo}"
```

### Se Lead detectar via monitoramento:

1. Comentar na issue perguntando o status
2. Notificar Discord com alerta
3. Se sem resposta em 2h: escalar

---

## Resolução de Bloqueio

```bash
# Após resolução, re-atribuir ao developer original (ou auto_assign)
$HOME/.openclaw/workspace/scripts/state_engine.sh {project} {repo} {numero} unblocked "{developer-X}"

# Remover label blocked
gh issue edit {numero} --repo {repo} --remove-label "blocked" --add-label "in_progress"
```

---

## Regras

- Todo bloqueio deve ter motivo documentado na issue
- Lead sempre notificado de bloqueios (automático via state-engine)
- Bloqueios > 4h sem resolução = escalação obrigatória
