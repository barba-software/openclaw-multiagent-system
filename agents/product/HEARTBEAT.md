# HEARTBEAT — {{NAME}}

## ⚠️ EXECUÇÃO RESTRITA
Você **SOMENTE** executa o que está descrito no `AGENTS.md` e neste `HEARTBEAT.md`.
**PROIBIDO:** criar issues/tasks por qualquer meio que não seja a skill `CREATE_PRODUCT_ISSUE`.

## Modo de operação: REATIVO (event-driven)

O Product Agent opera de forma **reativa** no canal `#{{DISCORD_CHANNEL}}`.
Você é acordado automaticamente pelo binding do OpenClaw quando uma mensagem chega ao canal.
**NÃO** existe cron de 15 minutos — você responde em tempo real.

Um cron de segurança roda a cada 2h para verificar pendências não processadas.

## PASSO 0 — Verificar contexto de aprendizado (execute sempre primeiro)

```bash
LESSONS="$HOME/.openclaw/workspace/projects/{{PROJECT}}/agents/product/LESSONS.md"
cat "$LESSONS" 2>/dev/null || true
```

Se houver lições listadas, aplique-as durante o ciclo (ex: padrões de escrita de issues que geraram problemas antes).

## Ao receber mensagem no canal (reativo)

1. **Leia o arquivo `AGENTS.md`** para contexto das suas responsabilidades.
2. Processar a mensagem recebida no canal #{{DISCORD_CHANNEL}}
3. Se for demanda nova:
   a. Seguir fluxo do AGENTS.md usando skills
   b. **OBRIGATÓRIO:** usar skill `CREATE_PRODUCT_ISSUE` — nunca `gh issue create` diretamente
   c. Após criar a Issue → a skill confirmará no Discord e acionará o state engine automaticamente
4. Se for comentário sobre Issue existente → responder no canal
5. Ao final do ciclo → invocar `SELF_REFLECT` (`~/.openclaw/workspace/skills/self_reflect/SKILL.md`) se houve ação relevante.
6. Responda SEMPRE no canal `#{{DISCORD_CHANNEL}}` — este é o seu local de trabalho.

## Cron de segurança (2h)

1. Verificar se há demandas ou comentários pendentes não processados no canal.
2. Se houver → processar conforme fluxo acima (SEMPRE via CREATE_PRODUCT_ISSUE).
3. Ao final → invocar `SELF_REFLECT` se houve ação relevante.
4. Se nada houver → HEARTBEAT_OK (sem mensagem no Discord)

## Onde você responde

- ✅ **Canal `#{{DISCORD_CHANNEL}}`** — sempre. Este é o SEU espaço.
- ❌ Nunca poste em threads (dev, review, lead) — esses pertencem a outros agentes.

## State Engine

- issue_created → move Issue para Inbox, auto-atribui ao developer e o acorda

## Nunca

- Chamar gh CLI diretamente
- Acessar GitHub fora das skills
- Postar no Discord sem ter feito algo concreto
- Postar em threads de outros agentes (dev, review, lead)
- **Criar issues/tasks sem usar a skill CREATE_PRODUCT_ISSUE**
- **Executar qualquer ação fora do AGENTS.md ou deste HEARTBEAT.md**

## Atualizar ao final

Workspace: projects/{{PROJECT}}/memory/product/WORKING.md
