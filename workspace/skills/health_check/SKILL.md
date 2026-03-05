---
name: "health_check"
description: "Verifica a integridade completa do sistema OpenClaw para um projeto."
---

# SKILL: HEALTH_CHECK

**Responsável:** Lead Agent  
**Permissão:** role=lead  
**Trigger:** Diário (via standup) ou sob demanda

---

## Protocolo

### 1. Executar script de health check

```bash
bash ~/.openclaw/workspace/scripts/health_check.sh {project}
```

### 2. Executar verify_provisioning

```bash
bash ~/.openclaw/workspace/scripts/verify_provisioning.sh {project} {repo}
```

### 3. Interpretar resultado e postar na thread lead

**Se tudo OK:**
```
🏥 Health Check — {project} — {timestamp}
✅ Sistema íntegro. Todos os checks passaram.
```

**Se houver avisos:**
```
🏥 Health Check — {project} — {timestamp}
⚠️ {N} avisos encontrados:
• {aviso 1}
• {aviso 2}
Ação tomada: {o que foi corrigido ou notificado}
```

**Se houver erros críticos:**
```
🚨 Health Check CRÍTICO — {project} — {timestamp}
❌ {N} erros encontrados:
• {erro 1}
• {erro 2}
Ação imediata necessária. @usuário precisa intervir.
```

### 4. Verificações manuais adicionais

```bash
# Crons ativos
openclaw cron list | grep {project}

# Skills presentes
ls ~/.openclaw/workspace/skills/

# Agentes ativos
openclaw agents list | grep {project}

# Issues inconsistentes (in_progress sem agente)
cat ~/.openclaw/workspace/projects/{project}/state.json | jq '
  .issues | to_entries
  | map(select(.value.status == "in_progress" and (.value.assigned_agent == null or .value.assigned_agent == "")))'
```

---

## Frequência recomendada

- Diariamente via DAILY_STANDUP (incluir resultado no relatório)
- Após qualquer intervenção manual no GitHub ou openclaw
- Quando usuário reportar comportamento inesperado
