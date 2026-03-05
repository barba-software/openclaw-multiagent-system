# HEARTBEAT — {{NAME}}

## PASSO 0 — Verificar contexto de aprendizado (execute sempre primeiro)

```bash
LESSONS="$HOME/.openclaw/workspace/projects/{{PROJECT}}/agents/product/LESSONS.md"
cat "$LESSONS" 2>/dev/null || true
```

Se houver lições listadas, aplique-as durante o ciclo (ex: padrões de escrita de issues que geraram problemas antes).

## A cada ciclo (15 min)

1. **Leia o arquivo `AGENTS.md`** para contexto das suas responsabilidades.
2. Verificar mensagens novas no canal #{{DISCORD_CHANNEL}}
3. Se houver demanda nova:
   a. Seguir fluxo do AGENTS.md usando skills
   b. Após criar a Issue → a skill confirmará no Discord e acionará o state engine automaticamente
4. Se houver comentário pendente em Issue → responder no Discord
5. Se nada houver → HEARTBEAT_OK (sem mensagem no Discord)

## State Engine

- issue_created → move Issue para Inbox, auto-atribui ao developer e o acorda

## Nunca

- Chamar gh CLI diretamente
- Acessar GitHub fora das skills
- Postar no Discord sem ter feito algo concreto

## Atualizar ao final

Workspace: projects/{{PROJECT}}/memory/product/WORKING.md
