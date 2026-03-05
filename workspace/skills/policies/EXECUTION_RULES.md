# EXECUTION RULES

## Regras de Skills

1. **Nenhuma skill pode ser usada fora da PERMISSIONS.md.**
2. **Nenhum agente pode criar skills** — apenas usar as globais.
3. **Todo agente deve ler AGENTS.md** no início de cada heartbeat.
4. **Local único de skills:** `~/.openclaw/workspace/skills/` — se não encontrar aqui, não existe.
5. Violação de regra deve ser reportada na thread do agente.

## Regras de Issues

6. Nenhuma Issue sem critérios de aceite verificáveis (binários, testáveis).
7. Nenhum código fora de Pull Request (nunca commit direto na main).
8. Nenhuma Issue criada sem passar por CREATE_PRODUCT_ISSUE.
9. Issues devem ser atribuídas ao board automaticamente — verificar se board existe antes de criar.

## Regras de Comunicação Discord

10. Cada agente opera APENAS em seu canal/thread designado.
11. **Avisos obrigatórios** devem ser postados antes de iniciar qualquer tarefa.
12. Nenhum agente fala no canal principal exceto o Product.
13. Lead nunca intervém no canal principal.

## Regras de Estado

14. Nenhuma transição de estado sem passar pelo state_engine.sh.
15. Nenhuma issue fechada manualmente (responsabilidade do state_engine via pr_merged).
16. state.json é a fonte da verdade — GitHub Board é espelho.
17. Developer começa sempre com capacity=1 e um único developer-1.

## Regras de Escalonamento

18. Scale developer só após confirmação explícita do usuário.
19. Lead propõe após 2 ciclos de saturação consecutivos.
20. Contador de saturação persiste em `memory/lead/saturation_count.txt`.

## Regras de Segurança

21. Nenhum secret no código ou em issues.
22. Nenhum merge sem revisão completa.
23. Logs de debug não devem conter tokens ou credentials.
