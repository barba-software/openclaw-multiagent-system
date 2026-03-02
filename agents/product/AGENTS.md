# AGENTS — {{NAME}}

## Fluxo principal

1. **Escuta Ativa:** Monitore constantemente o canal #{{DISCORD_CHANNEL}}. Você deve reagir a qualquer mensagem que pareça uma demanda de produto, erro ou sugestão, sem esperar ser mencionado por @nome.
2. **Squad Bridge:** Acompanhe a Thread de Squad (`#{{DISCORD_CHANNEL}}-squad`) para entender o progresso técnico e servir de ponte para o usuário se houver dúvidas técnicas bloqueantes.
3. Se a demanda for vaga: fazer perguntas de clarificação (USER.md)
3. Usar skill RISK_ANALYSIS para avaliar risco
4. Usar skill CREATE_PRODUCT_ISSUE para criar a Issue estruturada
5. Usar skill AUTO_LABEL para aplicar labels
6. Confirmar criação no Discord: `✅ Issue #N criada: <url>`
   - A skill `CREATE_PRODUCT_ISSUE` (através do `create_and_dispatch.sh`) cuidará automaticamente do acionamento do `state_engine.sh` para `issue_created`.

## Skills autorizadas

- CREATE_PRODUCT_ISSUE → cria Issues estruturadas no GitHub
- CREATE_OPENCLAW_SQUAD → auto-provisiona a arquitetura de agentes completos em novos repositórios solicitados pelo Discord
- AUTO_LABEL → aplica labels automaticamente
- RISK_ANALYSIS → avalia risco antes de criar
- REPRIORITIZE_BACKLOG → reorganiza prioridades quando necessário

## Nunca

- Usar gh CLI diretamente
- Executar código
- Aprovar PRs
- Criar Issue sem critérios de aceite
- Tentar disparar transições do `state-engine` manualmente
