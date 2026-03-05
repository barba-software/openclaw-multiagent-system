# HEARTBEAT — {{NAME}}

## PASSO 0 — Carregar contexto persistente (execute sempre primeiro)

```bash
WORKING="$HOME/.openclaw/workspace/projects/{{PROJECT}}/agents/developer/WORKING.md"
LESSONS="$HOME/.openclaw/workspace/projects/{{PROJECT}}/agents/developer/LESSONS.md"
cat "$WORKING"
cat "$LESSONS" 2>/dev/null || true
```

- Se `STATUS: em andamento` → issue foi interrompida no ciclo anterior. Retome o EXECUTE_ISSUE pulando para a etapa indicada em `STEP:` — não recomece do zero.
- Se `STATUS: idle` → verifique a fila normalmente.
- Aplique as lições listadas em `LESSONS.md` durante este ciclo.

## A cada ciclo (15 min)

1. **Leia o arquivo `AGENTS.md`** para entender o seu fluxo de trabalho, regras e habilidades permitidas.
2. Use a skill `EXECUTE_ISSUE` para verificar a fila. Sua chave no `state.json` é **`developer-1`**. Todos os anúncios no Discord usam `openclaw message send` conforme descrito no `AGENTS.md`.
3. Se houver Issue em `in_progress` ou `blocked` atribuída a você → executar EXECUTE_ISSUE passo a passo.
4. Se houver PR devolvida pelo reviewer (estado `blocked`) → seção "Processando feedback de Review" do EXECUTE_ISSUE.
5. Se houver PR dependente travada ou gargalo crônico → usar a skill `BLOCK_DETECTION`.
6. Se nada houver → HEARTBEAT_OK

## State Engine

- pr_created → move Issue para Review e acorda reviewer
- blocked → move Issue para Blocked e acorda lead

## Nunca

- Usar --assignee @me (issues não têm assignee neste projeto)
- Postar no Discord em ciclos sem eventos
- Commitar direto na main

## Atualizar ao final

Workspace: projects/{{PROJECT}}/memory/developer/WORKING.md
