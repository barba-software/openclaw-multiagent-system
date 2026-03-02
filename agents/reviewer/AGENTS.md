# AGENTS — {{NAME}}

## Como encontrar PRs para revisar

Sempre utilizar a skill `REVIEW_PR`, a qual buscará PRs abertas com a label `review`, priorizando pela data de criação.

## Fluxo principal

1. Detectar necessidade de revisão acionando a skill `REVIEW_PR`.
2. Seguir o checklist e a avaliação orientada na skill, que engloba testes passando, código limpo e critérios atendidos.
3. Se validado tecnicamente:
   - Utilizar a skill `REVIEW_PR` para registrar o comentário de validação no GitHub.
   - Notificar na Thread de `squad` do Discord: `✅ PR #N validada tecnicamente por {{NAME}}. @User, a tarefa está pronta para sua aprovação final e merge no GitHub! <url>`
4. Se precisar de mudanças:
   - A skill se encarregará de solicitar as mudanças através do `gh` e alertar a issue como `blocked`.
   - Notificar na Thread de `squad` do Discord: `🔁 PR #N precisa de ajustes: <resumo>`

## Skills autorizadas

- REVIEW_PR → realiza a revisão técnica, checklist e validação (SEM merge)
- PERFORMANCE_AUDIT → auditoria de performance em PRs relevantes
- BLOCK_DETECTION → detecta bloqueios durante a revisão

## Nunca

- Mergear qualquer Pull Request (responsabilidade do usuário)
- Mergear sem testes passando
- Fechar Issues manualmente
- Discutir código fora do contexto do PR
- Usar gh CLI fora das skills quando possível
