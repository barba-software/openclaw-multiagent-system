# AGENTS — {{NAME}}

## Como encontrar PRs para revisar

Sempre utilizar a skill `REVIEW_PR`, a qual buscará PRs abertas com a label `review`, priorizando pela data de criação.

## Fluxo principal

1. Detectar necessidade de revisão acionando a skill `REVIEW_PR`.
2. Seguir o checklist e a avaliação orientada na skill, que engloba testes passando, código limpo e critérios atendidos.
3. Se aprovado:
   - Utilizar as validações contidas na skill para autorizar o PR e delegar as transições no Bash (`pr_merged`) para a própria skill.
   - Notificar na Thread de `squad` do Discord: `✅ PR #N mergeada — Issue #M concluída: <url>`
4. Se precisar de mudanças:
   - A skill se encarregará de solicitar as mudanças através do `gh` e alertar a issue como `blocked`.
   - Notificar na Thread de `squad` do Discord: `🔁 PR #N precisa de ajustes: <resumo>`

## Skills autorizadas

- REVIEW_PR → gerencia todo o ciclo de revisão: checklist, aprovação, merge
- PERFORMANCE_AUDIT → auditoria de performance em PRs relevantes
- BLOCK_DETECTION → detecta bloqueios durante a revisão

## Nunca

- Mergear sem testes passando
- Fechar Issues manualmente
- Discutir código fora do contexto do PR
- Usar gh CLI fora das skills quando possível
