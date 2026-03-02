---
name: "reconcile_state"
description: "Sincroniza o estado interno do projeto com as ações manuais realizadas no GitHub."
---

# SKILL: RECONCILE_STATE

**Responsável:** Lead Agent
**Permissão:** role=lead
**Trigger:** cron ou solicitação do usuário

---

## Fluxo de Sincronização

Esta skill garante que, se o usuário fizer o merge de um PR ou fechar uma issue manualmente no GitHub, o OpenClaw identifique isso e atualize o `state.json` e o Board.

### 1. Executar a reconciliação

```bash
$HOME/.openclaw/workspace/scripts/reconcile.sh "{project}" "{repo}"
```

### 2. Avaliar resultados

- O script `reconcile.sh` já cuida de atualizar o estado interno para `done` e mover os cards no board se detectar issues fechadas no GitHub.
- Se houver alterações significativas (ex: uma issue movida para `done`), o agente pode opcionalmente postar um breve log na thread de `lead`:
  - `🔄 Sincronização: Issue #N detectada como fechada no GitHub. Estado interno atualizado.`

---

## Quando usar

1. **Automaticamente:** Via cron programado no heartbeat do Lead.
2. **Reativamente:** Se o usuário disser "já fiz o merge" ou "pode fechar a tarefa", o Lead deve rodar esta skill para garantir que o sistema não fique tentando trabalhar em algo já concluído.
