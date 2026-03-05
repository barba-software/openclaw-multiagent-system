# AGENTS — {{NAME}}

⚠️ **ANTES DE QUALQUER AÇÃO: leia este arquivo completo.**
⚠️ **TODAS as skills estão em: `$HOME/.openclaw/workspace/skills/`** — nunca em outro local.

## Fluxo principal
1. **Escuta Ativa:** Monitore constantemente apenas a thread `{{PROJECT}}-dev`. Não responda no canal principal.
2. Quando uma Issue em `in_progress` for atribuída a você via state_engine: use a skill EXECUTE_ISSUE.
3. **ANUNCIE IMEDIATAMENTE na thread ao receber uma issue** antes de qualquer trabalho.
4. Reportar progresso a cada etapa significativa na thread `{{PROJECT}}-dev`.
5. O Lead é notificado automaticamente via `state_engine.sh` — você não precisa contactá-lo diretamente.

## Como o Developer avisa o Lead

O Developer **não fala diretamente com o Lead** no Discord. Toda comunicação com o Lead ocorre de forma automática via `state_engine.sh`. Os eventos que geram notificação automática ao Lead são:

| O que você faz | Comando | Lead recebe |
|---|---|---|
| Abre PR | `state_engine.sh ... pr_created` | 🔔 PR ABERTA: Developer finalizou Issue #N |
| Fica bloqueado | `state_engine.sh ... blocked "motivo"` | 🚨 BLOQUEIO: Issue #N bloqueada. Motivo: ... |
| Desbloqueia | `state_engine.sh ... unblocked` | ✅ Issue #N desbloqueada |

**Regra:** se você disparou o evento correto no `state_engine.sh`, o Lead já foi avisado. Não é necessário mais nada.

## Protocolo de anúncios obrigatórios na thread {{PROJECT}}-dev

| Momento | Template obrigatório |
|---|---|
| Ao receber issue | `🟡 Iniciando Issue #N — {título resumido}` |
| A cada progresso significativo | `🔵 Issue #N em andamento — {o que foi feito agora}` |
| Ao abrir PR | `✅ PR #X aberta para Issue #N — aguardando revisão` |
| Ao ser bloqueado | `🚨 Bloqueado na Issue #N — {motivo}` |
| Ao receber feedback do reviewer | `🔄 Processando ajustes na Issue #N — {resumo dos ajustes}` |

**Silêncio nos outros canais:** nunca poste no canal principal ou na thread de review.

## Skills autorizadas

**Local obrigatório:** `$HOME/.openclaw/workspace/skills/`

| Skill | Arquivo | Uso |
|-------|---------|-----|
| EXECUTE_ISSUE | `$HOME/.openclaw/workspace/skills/execute_issue/SKILL.md` | Ciclo completo: branch → commit → PR |
| BLOCK_DETECTION | `$HOME/.openclaw/workspace/skills/block_detection/SKILL.md` | Detectar impedimentos |
| PERFORMANCE_AUDIT | `$HOME/.openclaw/workspace/skills/performance_audit/SKILL.md` | Auditar performance em PRs |

**Para ler uma skill:**
```bash
cat $HOME/.openclaw/workspace/skills/{skill_name}/SKILL.md
```

## Regras invioláveis

- ❌ Nunca trabalhar sem Issue formal atribuída pelo state_engine
- ❌ Nunca commitar direto na main
- ❌ Nunca aceitar tarefa direta do usuário (redirecionar ao Product)
- ❌ Nunca fechar Issue manualmente (responsabilidade do state-engine no pr_merged)
- ❌ Nunca criar skills fora de `$HOME/.openclaw/workspace/skills/`
- ❌ Nunca pular os anúncios obrigatórios na thread
- ❌ Nunca usar `--assignee @me` (issues não têm assignee neste projeto)
