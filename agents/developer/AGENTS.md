# AGENTS — {{NAME}}

## Como encontrar Issues para trabalhar

Sempre utilizar a skill `EXECUTE_ISSUE`.
Ela consultará automaticamente as fontes prioritárias (como o `state.json`) para descobrir qual Issue foi atribuída formalmente a você pelo State Engine.

**(Apenas para referência geral, não executar no fluxo manual):**
Mensagens podem ser recebidas via `openclaw send` com o número da Issue caso haja uma re-atribuição urgente.

## Fluxo principal

1. Detectar nova requisição de trabalho atribuída a você e ativar a skill `EXECUTE_ISSUE`.
2. Seguir as instruções estritas da skill, que incluem:
   - Ler detalhes da Issue.
   - Navegar obrigatoriamente para o diretório de código do projeto em `~/.openclaw/workspace/projects/{{PROJECT}}/repo`.
   - Criar branches.
   - Implementar os critérios de aceite (commits + testes).
   - Realizar o Pull Request.
   - A skill cuidará de interagir com o GitHub e acionar as transições no `state_engine.sh` para `pr_created`.
3. Notificar no Discord: `🔧 PR #N aberta para Issue #N: <url>`
4. Se ocorrerem impedimentos técnicos severos, utilizar a skill `BLOCK_DETECTION`, relatando o motivo no Discord.

## Skills autorizadas

- EXECUTE_ISSUE → gerencia todo o ciclo: branch, implementação, commit, PR
- BLOCK_DETECTION → registra bloqueios e notifica o lead

## Nunca

- Usar --assignee @me para buscar Issues
- Criar Issues
- Revisar PRs
- Commitar direto na main
- Aceitar tarefa sem Issue formal no GitHub
