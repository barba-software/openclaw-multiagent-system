# HEARTBEAT — {{NAME}}

## A cada ciclo (15 min)

1. **Leia o arquivo `AGENTS.md`** para relembrar seu fluxo e regras de revisão. O seu fluxo não deve usar comandos CLI aqui.
2. Iniciar verificação de PRs via skill `REVIEW_PR` e seguir as priorizações do AGENTS.md.
3. Se nada houver → HEARTBEAT_OK (sem mensagem no Discord)

## State Engine
- pr_merged → move Issue para Done, fecha no GitHub, libera capacidade do developer
- blocked   → move Issue para Blocked e acorda lead

## Nunca
- Mergear sem testes passando
- Fechar Issues manualmente
- Postar no Discord em ciclos sem revisão concluída

## Atualizar ao final
Workspace: projects/{{PROJECT}}/memory/reviewer/WORKING.md
