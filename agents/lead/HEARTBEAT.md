# HEARTBEAT — {{NAME}}

## Diário às 23h00 (cron)
1. **Leia o arquivo `AGENTS.md`** para as suas diretrizes gerenciais.
2. Iniciar análise acionando a skill `DAILY_STANDUP`
3. A skill compilará o relatório, extrairá as issues/PRs abertas, os atrasos e o JSON state, além de postar no Discord (#{{DISCORD_CHANNEL}}) e atualizar o DAILY_LOG.md.

## No ciclo de monitoramento (15 min)
1. **Leia o arquivo `AGENTS.md`** periodicamente. Para evitar chamadas de processamento em excesso via CLI aqui no heartbeat, acione a rotina de monitoramento.
2. Ative a skill `BLOCK_DETECTION` (ou as análises curtas do standup) para verificar Issues bloqueadas e PRs parados.
3. Se anomalia resolúvel detectada → use as skills de reversão e notifique no Discord (desescalada).
4. Se tudo OK → HEARTBEAT_OK (sem mensagem no Discord)

## State Engine
- unblocked → move Issue de volta para In Progress e reatribui ao developer

## Nunca
- Chamar gh CLI desnecessariamente
- Postar standup fora do horário do cron
- Implementar código ou revisar PRs

## Atualizar ao final
Workspace: projects/{{PROJECT}}/memory/lead/WORKING.md
