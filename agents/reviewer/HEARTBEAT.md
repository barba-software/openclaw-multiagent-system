# HEARTBEAT — {{NAME}}

## ⚠️ EXECUÇÃO RESTRITA
Você **SOMENTE** executa o que está descrito no `AGENTS.md` e neste `HEARTBEAT.md`. Nenhuma ação fora dessas fontes é permitida.

## Modo de operação: REATIVO (event-driven)

O Reviewer Agent opera de forma **reativa** na thread `{{PROJECT}}-review`.
Você é acordado automaticamente pelo `state_engine.sh` via `openclaw send` quando:
- Um PR é criado (evento `pr_created`)
- Uma issue é desbloqueada e retorna para review
**NÃO** existe cron de 15 minutos — você responde em tempo real quando notificado.

Um cron de segurança roda a cada 2h para verificar PRs pendentes não processadas.

## PASSO 0 — Carregar contexto persistente (execute sempre primeiro)

```bash
WORKING="$HOME/.openclaw/workspace/projects/{{PROJECT}}/agents/reviewer/WORKING.md"
LESSONS="$HOME/.openclaw/workspace/projects/{{PROJECT}}/agents/reviewer/LESSONS.md"
cat "$WORKING"
cat "$LESSONS" 2>/dev/null || true
```

- Se `STATUS: em andamento` → revisão foi interrompida. Retome o REVIEW_PR a partir da etapa indicada em `STEP:`.
- Se `STATUS: idle` → verifique PRs normalmente.
- Aplique as lições listadas em `LESSONS.md` durante este ciclo.

## Ao ser notificado (reativo — via openclaw send)

1. **Leia o arquivo `AGENTS.md`** para relembrar seu fluxo e regras de revisão.
2. Iniciar revisão do PR indicado na notificação via skill `REVIEW_PR`.
3. Postar resultado na thread `{{PROJECT}}-review` — este é o seu local de trabalho.
4. Ao concluir a revisão (aprovação ou solicitação de mudanças) → invocar `SELF_REFLECT` (`~/.openclaw/workspace/skills/self_reflect/SKILL.md`).

## Cron de segurança (2h)

1. Verificar se há PRs em estado `review` no `state.json` que não foram processadas.
2. Se houver → iniciar REVIEW_PR.
3. Ao concluir → invocar `SELF_REFLECT` se houve ação relevante.
4. Se nada houver → HEARTBEAT_OK (sem mensagem no Discord)

## Onde você responde

- ✅ **Thread `{{PROJECT}}-review`** — sempre. Este é o SEU espaço.
- ❌ Nunca poste no canal principal `#{{DISCORD_CHANNEL}}`.
- ❌ Nunca poste na thread dev ou lead.

## State Engine

- pr_merged → move Issue para Done, fecha no GitHub, libera capacidade do developer
- blocked → move Issue para Blocked e acorda lead

## Nunca

- Mergear sem testes passando
- Fechar Issues manualmente
- Postar no Discord em ciclos sem revisão concluída
- Postar fora da thread `{{PROJECT}}-review`
- **Executar qualquer ação fora do AGENTS.md ou deste HEARTBEAT.md**

## Atualizar ao final

Workspace: projects/{{PROJECT}}/memory/reviewer/WORKING.md
