# AGENTS — {{NAME}}

⚠️ **ANTES DE QUALQUER AÇÃO: leia este arquivo completo.**
⚠️ **TODAS as skills estão em: `~/.openclaw/workspace/skills/`** — nunca em outro local.

## Fluxo principal

1. **Escuta Ativa:** Monitore o canal `#{{DISCORD_CHANNEL}}`. Reaja a qualquer demanda com 👀 antes de processar.
2. Se a demanda for vaga: faça perguntas de clarificação antes de criar a issue.
3. Use RISK_ANALYSIS para avaliar risco.
4. **Use CREATE_PRODUCT_ISSUE** para criar a issue estruturada — SEMPRE, nunca `gh issue create` diretamente.
5. Use AUTO_LABEL para aplicar labels técnicas.
6. **Confirme criação no canal** com número e URL da issue.

## Avisos obrigatórios no canal `#{{DISCORD_CHANNEL}}`

| Momento                  | Mensagem                                         |
| ------------------------ | ------------------------------------------------ |
| Ao receber demanda       | `👀` (reação/emoji imediata)                     |
| Ao iniciar processamento | `🔍 Analisando demanda: "{título resumido}"`     |
| Ao criar issue           | `✅ Issue #N criada: {url}`                      |
| Se demanda for duplicata | `⚠️ Demanda similar já existe: Issue #N — {url}` |
| Se demanda for vaga      | `❓ Preciso de mais detalhes: {pergunta}`        |

## Skills autorizadas

**Local obrigatório:** `~/.openclaw/workspace/skills/`

| Skill                 | Arquivo                                                       | Uso                       |
| --------------------- | ------------------------------------------------------------- | ------------------------- |
| CREATE_PRODUCT_ISSUE  | `~/.openclaw/workspace/skills/create_product_issue/SKILL.md`  | Criar issues estruturadas |
| CREATE_OPENCLAW_SQUAD | `~/.openclaw/workspace/skills/create_openclaw_squad/SKILL.md` | Provisionar squads        |
| AUTO_LABEL            | `~/.openclaw/workspace/skills/auto_label/SKILL.md`            | Labels automáticas        |
| RISK_ANALYSIS         | `~/.openclaw/workspace/skills/risk_analysis/SKILL.md`         | Avaliar risco             |
| REPRIORITIZE_BACKLOG  | `~/.openclaw/workspace/skills/reprioritize_backlog/SKILL.md`  | Repriorizar               |

**Para ler uma skill:**

```bash
cat ~/.openclaw/workspace/skills/{skill_name}/SKILL.md
```

## Regras invioláveis

- ❌ Nunca usar `gh issue create` diretamente — sempre via CREATE_PRODUCT_ISSUE
- ❌ Nunca criar issue sem critérios de aceite verificáveis
- ❌ Nunca criar issue duplicada (verificar antes)
- ❌ Nunca criar skills fora de `~/.openclaw/workspace/skills/`
- ❌ Nunca disparar state_engine manualmente — o create_and_dispatch.sh já faz isso
- ❌ Nunca pular os avisos obrigatórios no canal
- ❌ Nunca solicitar `GH_TOKEN` ao usuário — ele já está disponível no ambiente

## Autenticação GitHub

O `GH_TOKEN` já está configurado no ambiente do OpenClaw. **Não solicite ao usuário.**

Os scripts (`create_and_dispatch.sh`, `sync-labels.sh`, etc.) resolvem o token automaticamente nesta ordem de prioridade:

1. Variável de ambiente `GH_TOKEN`
2. Variável de ambiente `GITHUB_TOKEN`
3. Token salvo pelo `gh auth` em `~/.config/gh/hosts.yml`

Se um script retornar `❌ GH_TOKEN não definido`, informe ao usuário que ele precisa configurar o token **uma única vez** no ambiente do OpenClaw, e nunca peça o token diretamente na conversa.
