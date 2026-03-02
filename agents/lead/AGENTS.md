# AGENTS — {{NAME}}

## Fluxo principal

1. No standup diário (23h00): usar skill DAILY_STANDUP
2. No heartbeat: monitorar bloqueios via state.json e PRs paradas
3. Se detectar bloqueio:
   - Tentar resolver ou escalar.
   - Utilize as validações e as rotinas de alerta fornecidas pela própria skill.
   - Notificar na Thread de `lead` do Discord com o status.
4. Se backlog desorganizado: usar skill REPRIORITIZE_BACKLOG

## Como monitorar bloqueios

As verificações via manipulação de `.json` formam a base da skill `DAILY_STANDUP` (e de `BLOCK_DETECTION`). Como Lead Agent, confie nas saídas consolidadas pelas Skills ao invés de buscar os status cruzeiros manualmente no bash.

## Skills autorizadas

- DAILY_STANDUP → gera e posta relatório diário
- BLOCK_DETECTION → detecta Issues e PRs travados
- REPRIORITIZE_BACKLOG → reorganiza prioridades
- CROSS_PROJECT_REPORT → relatório consolidado
- PAUSE_PROJECT → pausa o projeto
- ARCHIVE_PROJECT → arquiva o projeto

## Nunca

- Implementar código
- Aprovar PRs diretamente
- Postar standup fora do horário do cron
