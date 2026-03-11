# Release Notes — v1.4.0

> Governança de Agentes, Auto-aprendizado e Comunicação Efetiva

## Como criar a tag e release após merge

```bash
git tag -a v1.4.0 -m "v1.4.0 — Governança de Agentes, Auto-aprendizado e Comunicação Efetiva"
git push origin v1.4.0
gh release create v1.4.0 --title "v1.4.0 — Governança de Agentes, Auto-aprendizado e Comunicação Efetiva" --notes-file RELEASE_NOTES_v1.4.0.md
```

---

## ✨ Novidades

### ⚡ Priorização de solicitações de mudança em PRs

PRs com mudanças solicitadas pelo Reviewer agora têm **prioridade máxima** sobre novas tarefas.

- `agents/developer/AGENTS.md`: novo bloco `⚡ PRIORIDADE MÁXIMA` com query do state.json para detectar issues bloqueadas vindas de review
- `agents/developer/HEARTBEAT.md`: **PASSO 0b** — verificação obrigatória de PRs com mudanças antes de qualquer outra ação
- `workspace/skills/execute_issue/SKILL.md`: novo passo **-1** de verificação de prioridade máxima
- `workspace/scripts/state_engine.sh`: notificação para developer ao receber feedback de review é agora marcada como `🚨 PRIORIDADE MÁXIMA`

### 📚 Auto-aprendizado Reforçado (SELF_REFLECT)

Todos os agentes agora invocam `SELF_REFLECT` ao concluir ciclos.

- `workspace/skills/execute_issue/SKILL.md`: novo **passo 12** — auto-aprendizado obrigatório ao concluir qualquer issue
- `workspace/skills/review_pr/SKILL.md`: nova seção de auto-aprendizado obrigatório após cada revisão
- `agents/developer/HEARTBEAT.md`: SELF_REFLECT ao concluir notificações reativas e ciclos de cron
- `agents/reviewer/HEARTBEAT.md`: SELF_REFLECT ao concluir revisões
- `agents/product/HEARTBEAT.md`: SELF_REFLECT ao concluir ciclos com ação
- `agents/lead/HEARTBEAT.md`: **PASSO 4** — curadoria de LESSONS.md a cada ciclo watchdog (não apenas no standup)

### 🔒 Exec Full para Todos os Agentes e Crons

Todos os crons agora executam em modo full, garantindo execução completa dos HEARTBEATs.

- `workspace/scripts/provision.sh`: flag `--exec full` adicionada a todos os `openclaw cron add`
- Mensagens de cron atualizadas com prefixo `(EXEC FULL)` e instrução explícita de execução completa
- Todos os `HEARTBEAT.md`: aviso `⚠️ EXECUÇÃO RESTRITA (EXEC FULL)` no cabeçalho

### 🚫 Proibição Estrita de Ações Fora do AGENTS.md/HEARTBEAT.md

É estritamente proibido que qualquer agente ou cron execute ações fora do que está descrito nos seus arquivos de protocolo.

- Seção **`⚠️ REGRA DE OURO — EXECUÇÃO RESTRITA`** adicionada ao topo de TODOS os `AGENTS.md` de todos os agentes
- `agents/product/AGENTS.md` e `HEARTBEAT.md`: reforço crítico do uso obrigatório de `CREATE_PRODUCT_ISSUE` (nunca `gh issue create` diretamente)
- Regras `Nunca` atualizadas em todos os `HEARTBEAT.md`
- `workspace/AGENTS.md`: seção de regras invioláveis adicionada

### 📡 Comunicação Mais Efetiva Entre Agentes

Notificações entre agentes agora contêm contexto estruturado com passos claros de ação.

- `workspace/scripts/state_engine.sh`:
  - Notificação para developer ao receber nova tarefa: inclui lista de verificações pré-execução
  - Notificação para developer ao receber feedback de review: marcada como PRIORIDADE MÁXIMA com passos de ação
  - Notificação para reviewer: inclui skill a usar, thread correta e aviso de protocolo
  - Notificação de desbloqueio: inclui instruções para retomar do WORKING.md

### 1️⃣ Uma Task por Vez por Developer

O sistema agora garante que cada developer trabalhe em no máximo 1 issue por vez.

- `agents/developer/AGENTS.md`: blocos `⚡ PRIORIDADE MÁXIMA` e `📌 REGRA DE CAPACIDADE` com queries para verificar estado atual
- `agents/developer/HEARTBEAT.md`: **PASSO 0c** — verificação de `active_issues` antes de aceitar nova tarefa
- `workspace/skills/execute_issue/SKILL.md`: **passo 0a** — verificação de capacidade com mensagem no Discord se ocupado
- `agents/lead/HEARTBEAT.md`: verificação **#12** no watchdog para detectar e alertar sobre violações de capacidade

---

## 📋 Arquivos Modificados

| Arquivo | Mudanças |
|---------|----------|
| `agents/developer/AGENTS.md` | Regra de ouro, prioridade de review, capacidade unitária |
| `agents/developer/HEARTBEAT.md` | PASSO 0b (prioridade review), PASSO 0c (capacidade), SELF_REFLECT |
| `agents/lead/AGENTS.md` | Regra de ouro, verificação de capacidade no fluxo |
| `agents/lead/HEARTBEAT.md` | Verificação #12, PASSO 4 (curadoria de lições), regras |
| `agents/product/AGENTS.md` | Regra de ouro, reforço do CREATE_PRODUCT_ISSUE |
| `agents/product/HEARTBEAT.md` | Execução restrita, SELF_REFLECT, reforço proibição |
| `agents/reviewer/AGENTS.md` | Regra de ouro, regras atualizadas |
| `agents/reviewer/HEARTBEAT.md` | Execução restrita, SELF_REFLECT, regras |
| `workspace/AGENTS.md` | Regra de ouro, regras invioláveis |
| `workspace/HEARTBEAT.md` | Aviso de execução restrita/full |
| `workspace/scripts/provision.sh` | `--exec full` em todos os crons, mensagens atualizadas |
| `workspace/scripts/state_engine.sh` | Notificações estruturadas com passos de ação |
| `workspace/skills/execute_issue/SKILL.md` | Passo -1 (prioridade), 0a (capacidade), 12 (SELF_REFLECT) |
| `workspace/skills/review_pr/SKILL.md` | Seção de SELF_REFLECT obrigatório |

**Full Changelog**: https://github.com/obarbadev/openclaw-multiagent-system/compare/v1.3.0...v1.4.0
