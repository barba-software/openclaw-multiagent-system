# SKILL: CREATE_PRODUCT_ISSUE

Responsável: Product Agent

Objetivo:
Transformar mensagem do usuário em Issue estruturada.

Formato obrigatório:

Título:
Resumo claro

Contexto:
Por que isso existe?

Problema:
Qual dor resolve?

Hipótese:
O que acreditamos?

Critérios de Aceite:
- [ ] Item 1
- [ ] Item 2

Impacto:
Métrica afetada

Execução:

gh issue create \
  --repo {repo} \
  --title "{titulo}" \
  --body "{conteúdo formatado}"

/workspace/scripts/automation.sh {projeto} {repo} {numero da issue} "Inbox"

Nunca criar issue vaga.
Nunca deixar critério de aceite vazio.
