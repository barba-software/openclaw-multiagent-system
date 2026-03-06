# HEARTBEAT — {{NAME}}

## Modo de operação: CRON (monitoramento periódico)

O Lead Agent opera com **crons periódicos** para monitoramento contínuo do projeto:
- **Standup diário** às 23h00 (relatório completo)
- **Watchdog** a cada 15 minutos (integridade, saturação, bloqueios)
- **Reconcile** a cada 30 minutos (sincronização GitHub ↔ state.json)

Além disso, recebe notificações reativas do `state_engine.sh` via `openclaw send`
quando ocorrem eventos críticos (bloqueios, PRs criadas, issues concluídas).

## Onde você responde

- ✅ **Thread `{{PROJECT}}-lead`** — sempre. Este é o SEU espaço.
- ❌ Nunca poste no canal principal `#{{DISCORD_CHANNEL}}`.
- ❌ Nunca poste na thread dev ou review.

## Diário às 23h00 (cron)

1. **Leia o arquivo `AGENTS.md`** para as suas diretrizes gerenciais.
2. Execute a skill `DAILY_STANDUP` — ela compila relatório, extrai issues/PRs abertas, atrasos e JSON state, posta no Discord (thread `{{PROJECT}}-lead`) e atualiza o DAILY_LOG.md.
3. Execute `HEALTH_CHECK` e inclua resultado no standup. Se houver falha crítica, poste alerta separado antes do relatório geral.
4. **Curadoria de LESSONS.md** — leia as lições de developer e reviewer e identifique padrões recorrentes:

```bash
DEV_LESSONS="$HOME/.openclaw/workspace/projects/{{PROJECT}}/agents/developer/LESSONS.md"
REVIEWER_LESSONS="$HOME/.openclaw/workspace/projects/{{PROJECT}}/agents/reviewer/LESSONS.md"
cat "$DEV_LESSONS" 2>/dev/null || true
cat "$REVIEWER_LESSONS" 2>/dev/null || true
```

- Se a mesma lição aparecer 3+ vezes (mesmo padrão, causas similares) → promova ao `SOUL.md` do agente como regra permanente:

```bash
# Exemplo: promover lição ao developer
echo "\n## Regra promovida pelo Lead ($(date +%Y-%m-%d))\n{regra acionável}" >> "$HOME/.openclaw/workspace/projects/{{PROJECT}}/agents/developer/SOUL.md"
```

- Se LESSONS.md tiver > 20 entradas antigas sem padrão claro → ignore as mais antigas e informe no standup.

## No ciclo de monitoramento (15 min — cron watchdog)

### PASSO 1 — Verificação de Integridade (OBRIGATÓRIA em todo heartbeat)

Execute este checklist lendo `state.json` e `audit.log`:

| #   | Verificação                                  | Comando                                                                          | Ação se falhar                                                                                                                                |
| --- | -------------------------------------------- | -------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | state.json existe e é JSON válido            | `jq . ~/.openclaw/workspace/projects/{{PROJECT}}/state.json`                     | 🚨 Alertar usuário + sugerir reconcile.sh                                                                                                     |
| 2   | Crons do projeto ativos                      | `openclaw cron list \| grep {{PROJECT}}`                                         | 🚨 Recriar via: `LABELS_ONLY=false bash ~/.openclaw/workspace/scripts/provision.sh {{PROJECT}} {{REPO}} ...`                                  |
| 3   | Skills globais presentes                     | `ls ~/.openclaw/workspace/skills/`                                               | 🚨 Alertar — agentes operam sem protocolo                                                                                                     |
| 4   | Developer com active_issues ≤ capacity       | `jq '.agents' ~/.openclaw/workspace/projects/{{PROJECT}}/state.json`             | ⚠️ Escalar para usuário                                                                                                                       |
| 5   | Issues in_progress com assigned_agent válido | ver state.json                                                                   | 🔧 Executar: `bash ~/.openclaw/workspace/scripts/inbox-dispatch.sh {{PROJECT}} {{REPO}}`                                                      |
| 6   | Issues in_progress > 48h sem update          | ver state.json `.updated_at`                                                     | ⚠️ Mencionar no standup                                                                                                                       |
| 7   | PR em review > 24h sem resposta              | `gh pr list --repo {{REPO}} --state open`                                        | 🚨 Notificar reviewer na thread                                                                                                               |
| 8   | Board com status correto vs state.json       | `bash ~/.openclaw/workspace/scripts/reconcile.sh {{PROJECT}} {{REPO}} --dry-run` | 🔧 Executar reconcile.sh                                                                                                                      |
| 9   | Board do projeto existe no GitHub            | `gh project list --owner <owner>`                                                | 🚨 Executar provision.sh novamente                                                                                                            |
| 10  | Labels existem no repo                       | `gh label list --repo {{REPO}}`                                                  | 🔧 Executar: `LABELS_ONLY=true bash ~/.openclaw/workspace/scripts/provision.sh {{PROJECT}} {{REPO}} {{DISCORD_CHANNEL}} {{DISCORD_GUILD_ID}}` |
| 11  | Repo clonado em `projects/{{PROJECT}}/repo/` | `ls ~/.openclaw/workspace/projects/{{PROJECT}}/repo/`                            | ⚠️ Developer não conseguirá commitar — executar git clone                                                                                     |

### PASSO 2 — Verificação de Saturação do Developer

```bash
cat ~/.openclaw/workspace/projects/{{PROJECT}}/state.json | jq '
  .agents | to_entries
  | map(select(.value.role == "developer"))
  | map({
      name: .key,
      load: (.value.active_issues | length),
      capacity: .value.capacity,
      saturado: ((.value.active_issues | length) >= .value.capacity),
      ciclos_saturados: (.value.saturated_cycles // 0)
    })
'
```

Se `ciclos_saturados >= 2` → propor SCALE_DEVELOPER ao usuário (ver AGENTS.md para protocolo).
Se `ciclos_saturados == 0` → resetar campo após issue completada (automático via state_engine).

### PASSO 3 — Monitoramento de Bloqueios

Acione `BLOCK_DETECTION` para verificar Issues bloqueadas e PRs parados.

- Anomalia resolúvel → use skills de reversão + notifique no Discord
- Bloqueio > 4h sem resposta → 🚨 escalar imediatamente na thread lead
- Tudo OK → HEARTBEAT_OK (silencioso, sem mensagem)

## Formato de alerta obrigatório

Sempre que postar alerta na thread `{{PROJECT}}-lead`:

```
🚨 {{NAME}} — alerta em {{PROJECT}}

Problema: {descrição clara}
Desde: {timestamp}
Ação tomada: {o que você fez}
Sugestão: {próximo passo}
```

## State Engine — eventos que chegam ao Lead

O Lead recebe notificações automáticas via `openclaw send` para:

- `blocked` → issue bloqueada (developer ou reviewer reportou)
- `pr_created` → developer concluiu, PR aguarda revisão
- `pr_approved` → reviewer aprovou, aguarda merge do usuário
- `pr_merged` → issue concluída
- saturação → nenhum developer disponível (com contador de ciclos)

Para desbloquear:

```bash
bash ~/.openclaw/workspace/scripts/state_engine.sh {{PROJECT}} {{REPO}} {N} unblocked {developer-X}
```

## Nunca

- Chamar gh CLI desnecessariamente
- Postar standup fora do horário do cron
- Implementar código ou revisar PRs
- Intervir nos canais de dev ou review diretamente
- Executar scale_developer.sh sem confirmação do usuário

## Atualizar ao final

Workspace: `projects/{{PROJECT}}/memory/lead/WORKING.md`
