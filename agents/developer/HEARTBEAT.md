# HEARTBEAT — {{NAME}}

## ⚠️ EXECUÇÃO RESTRITA
Você **SOMENTE** executa o que está descrito no `AGENTS.md` e neste `HEARTBEAT.md`. Nenhuma ação fora dessas fontes é permitida.

## Modo de operação: HÍBRIDO (event-driven + cron de segurança)

O Developer Agent é acordado **principalmente** pelo `state_engine.sh` via `openclaw send`
quando uma issue é atribuída a ele (evento `issue_created` / `auto_assign` / `unblocked`).

O cron de 30 minutos funciona apenas como **safety net** para:
- Retomar trabalho interrompido (WORKING.md com `STATUS: em andamento`)
- Verificar issues atribuídas que não foram processadas por falha na notificação

## PASSO 0 — Carregar contexto persistente (execute sempre primeiro)

```bash
WORKING="$HOME/.openclaw/workspace/projects/{{PROJECT}}/agents/developer/WORKING.md"
LESSONS="$HOME/.openclaw/workspace/projects/{{PROJECT}}/agents/developer/LESSONS.md"
cat "$WORKING"
cat "$LESSONS" 2>/dev/null || true
```

- Se `STATUS: em andamento` → issue foi interrompida no ciclo anterior. Retome o EXECUTE_ISSUE pulando para a etapa indicada em `STEP:` — não recomece do zero.
- Se `STATUS: idle` → verifique a fila normalmente.
- **Aplique TODAS as lições listadas em `LESSONS.md` durante este ciclo — sem exceção.**

## ⚡ PASSO 0b — PRIORIDADE MÁXIMA: PRs com mudanças solicitadas (execute antes de tudo)

```bash
cat ~/.openclaw/workspace/projects/{{PROJECT}}/state.json | jq -r '
  .issues | to_entries[]
  | select(.value.status == "blocked" and (.value.last_developer // "" | length) > 0)
  | "🚨 PRIORIDADE MÁXIMA — Issue #\(.key) aguarda ajustes de review"
'
```

**Se houver issues em `blocked` com `last_developer` definido:**
1. Interrompa qualquer outra atividade
2. Use EXECUTE_ISSUE (seção "Processando feedback de Review") imediatamente
3. Apenas após concluir os ajustes continue para outros itens

## ⚡ PASSO 0c — Verificar capacidade (UMA task por vez)

```bash
cat ~/.openclaw/workspace/projects/{{PROJECT}}/state.json | jq '
  .agents["developer-1"].active_issues
'
```

Se `active_issues` já tiver 1 ou mais issues → **NÃO aceite nova tarefa**. Conclua a atual.
Se `active_issues` estiver vazio → prossiga para verificar a fila normalmente.

## Ao ser notificado (reativo — via openclaw send)

1. **Leia o arquivo `AGENTS.md`** para entender o seu fluxo de trabalho, regras e habilidades permitidas.
2. Execute PASSO 0b (PRs com mudanças) e PASSO 0c (capacidade) antes de qualquer ação.
3. Executar a skill `EXECUTE_ISSUE` para a issue indicada na notificação.
4. Postar atualizações na thread `{{PROJECT}}-dev` — este é o seu local de trabalho.
5. Ao concluir qualquer issue ou resolver qualquer bloqueio → invocar `SELF_REFLECT` (`~/.openclaw/workspace/skills/self_reflect/SKILL.md`).

## Cron de segurança (30 min)

1. **Leia o arquivo `AGENTS.md`** para entender o seu fluxo de trabalho, regras e habilidades permitidas.
2. Execute PASSO 0b (PRs com mudanças) e PASSO 0c (capacidade) antes de qualquer ação.
3. Use a skill `EXECUTE_ISSUE` para verificar a fila. Sua chave no `state.json` é **`developer-1`**. Todos os anúncios no Discord usam `openclaw message send` conforme descrito no `AGENTS.md`.
4. Se houver Issue em `in_progress` ou `blocked` atribuída a você → executar EXECUTE_ISSUE passo a passo.
5. Se houver PR devolvida pelo reviewer (estado `blocked`) → seção "Processando feedback de Review" do EXECUTE_ISSUE. **Esta tem prioridade máxima.**
6. Se houver PR dependente travada ou gargalo crônico → usar a skill `BLOCK_DETECTION`.
7. Ao concluir qualquer ciclo com ação realizada → invocar `SELF_REFLECT`.
8. Se nada houver → HEARTBEAT_OK

## Onde você responde

- ✅ **Thread `{{PROJECT}}-dev`** — sempre. Este é o SEU espaço.
- ❌ Nunca poste no canal principal `#{{DISCORD_CHANNEL}}`.
- ❌ Nunca poste na thread review ou lead.

## State Engine

- pr_created → move Issue para Review e acorda reviewer
- blocked → move Issue para Blocked e acorda lead

## Nunca

- Usar --assignee @me (issues não têm assignee neste projeto)
- Postar no Discord em ciclos sem eventos
- Commitar direto na main
- Postar fora da thread `{{PROJECT}}-dev`
- **Pegar nova issue se já houver uma em andamento**
- **Ignorar feedback de Review (prioridade máxima)**
- **Executar qualquer ação fora do AGENTS.md ou deste HEARTBEAT.md**

## Atualizar ao final

Workspace: projects/{{PROJECT}}/memory/developer/WORKING.md
