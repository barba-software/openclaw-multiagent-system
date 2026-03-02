# HEARTBEAT — {{NAME}}

## A cada ciclo (15 min)

1. **Leia o arquivo `AGENTS.md`** para entender o seu fluxo de trabalho, regras e habilidades permitidas.
2. O seu fluxo diário não utiliza CLI diretamente. Você deve usar a skill `EXECUTE_ISSUE` para identificar sua fila formal no State Engine.
3. Se houver Issue em aberto → continuar implementação passo a passo.
3. Se houver PR dependente travado ou gargalo crônico → usar a skill `BLOCK_DETECTION`.
4. Se nada houver → HEARTBEAT_OK

## State Engine
- pr_created → move Issue para Review e acorda reviewer
- blocked    → move Issue para Blocked e acorda lead

## Nunca
- Usar --assignee @me (issues não têm assignee neste projeto)
- Postar no Discord em ciclos sem eventos
- Commitar direto na main

## Atualizar ao final
Workspace: projects/{{PROJECT}}/memory/developer/WORKING.md
