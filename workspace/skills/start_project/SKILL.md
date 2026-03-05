---
name: "start_project"
description: "Inicia um novo projeto dentro do sistema OpenClaw, criando toda a estrutura necessária: Discord, board, agentes, crons, labels e repo."
---

# START_PROJECT

**Responsável:** Lead Global  
**Permissão:** role=lead-global  
**Ferramentas:** `exec`

---

## Como o openclaw se integra ao Discord

O openclaw **não cria** canais de texto nem threads normais via CLI.
O `provision.sh` agora tenta criar via **Discord REST API** usando o bot token.

Se a criação via API falhar (permissões insuficientes), o fluxo cai para modo manual:
o agente solicita os IDs ao usuário e o `rebind_threads.sh` faz o re-bind.

Envio de mensagem ao Discord (documentação oficial):

```bash
openclaw message send --channel discord --target channel:<ID> --message "texto"
```

Acordar agente internamente:

```bash
openclaw send --agent <agentId> --message "texto"
```

---

## O que o provision.sh cria

| Etapa        | O que faz                                                                                 |
| ------------ | ----------------------------------------------------------------------------------------- |
| Discord      | Tenta criar canal + 3 threads via API; registra IDs no openclaw.json                      |
| Workspaces   | Instancia SOUL/AGENTS/HEARTBEAT/USER/WORKING para cada agente                             |
| Agentes      | `openclaw agents add` + bindings por ID no openclaw.json                                  |
| Crons        | product-hb, dev-hb, review-hb, lead-standup, lead-reconcile, lead-watchdog                |
| Labels       | inbox, in_progress, review, blocked, done, agent:product, agent:developer, agent:reviewer |
| Board        | GitHub Projects com colunas: Inbox · In Progress · Review · Blocked · Done                |
| Repo         | `git clone` em `projects/{project}/repo/`                                                 |
| State        | state.json inicial (1 developer, capacity=1)                                              |
| Registry     | Entrada no registry.json global                                                           |
| Health check | Verificação pós-provisionamento automática                                                |
| Boas-vindas  | Mensagem no canal Discord                                                                 |

---

## Workflow

### 1. Coletar parâmetros

| Parâmetro | Exemplo              | Obrigatório                |
| --------- | -------------------- | -------------------------- |
| `project` | `meu-backend`        | ✅ sem espaços             |
| `repo`    | `owner/meu-backend`  | ✅                         |
| `channel` | `meu-backend`        | ✅ sem `#`                 |
| `guildId` | `123456789012345678` | ✅ ID numérico do servidor |

Os IDs de canal e threads (`CHANNEL_ID`, `DEV_THREAD_ID`, `REVIEW_THREAD_ID`, `LEAD_THREAD_ID`)
são **opcionais** — o `provision.sh` tentará criá-los via Discord API automaticamente.

Se algum estiver faltando, pergunte antes de continuar.

### 2. Confirmar com o usuário

```
Vou provisionar:
• Projeto: {project}
• Repo:    {repo}
• Canal:   #{channel} (guild: {guildId})

O provision.sh tentará criar o canal e threads automaticamente via Discord API.
Se falhar, solicitarei os IDs manualmente.

Confirma? (sim/não)
```

### 3. Validar que o setup foi executado

O usuário deve ter rodado o `setup.sh` antes de provisionar qualquer projeto. Esse script popula `~/.openclaw/workspace/` a partir do repositório clonado. Valide antes de continuar:

```bash
exec("bash", "-c", "
  MISSING=0
  [ ! -d \"$HOME/.openclaw/workspace/agents\" ]  && echo 'AUSENTE: $HOME/.openclaw/workspace/agents/'  && MISSING=1
  [ ! -d \"$HOME/.openclaw/workspace/skills\" ]  && echo 'AUSENTE: $HOME/.openclaw/workspace/skills/'  && MISSING=1
  [ ! -d \"$HOME/.openclaw/workspace/scripts\" ] && echo 'AUSENTE: $HOME/.openclaw/workspace/scripts/' && MISSING=1

  if [ \$MISSING -eq 1 ]; then
    echo ''
    echo 'O setup ainda não foi executado. Siga os passos abaixo:'
    echo ''
    echo '  cd ~/.openclaw'
    echo '  git clone https://github.com/barba-software/openclaw-multiagent-system.git'
    echo '  cd openclaw-multiagent-system'
    echo '  bash setup.sh'
    echo ''
    echo 'O setup.sh copiará agents/, skills/ e scripts/ para ~/.openclaw/workspace/'
    echo 'e solicitará o nome do agente principal (Lead / Gerente Geral).'
    exit 1
  fi

  echo 'Setup validado. Prosseguindo...'
")
```

### 4. Executar provision.sh

```bash
exec("bash", "$HOME/.openclaw/workspace/scripts/provision.sh",
  "{project}", "{repo}", "{channel}", "{guildId}")
```

O script é idempotente — reexecutar é seguro.
Ele criará canal/threads via Discord API e registrará os IDs automaticamente.

### 5. Verificar IDs Discord no output

Após o provision.sh, verifique o output. Se algum ID ficou vazio:

```
IDs Discord registrados:
  Canal principal:  <não configurado>   ← precisa de ação manual
  Thread dev:       <não configurado>
  ...
```

Nesse caso, solicite ao usuário que crie manualmente e execute:

```bash
exec("bash", "$HOME/.openclaw/workspace/scripts/rebind_threads.sh",
  "{project}", "{channel}", "{guildId}")
```

### 6. Avaliar resultado

**Se provision.sh falhar:**

- Exiba o erro completo
- Não prossiga

| Erro                                | Causa                                  | Solução                                                         |
| ----------------------------------- | -------------------------------------- | --------------------------------------------------------------- |
| `Template ausente`                  | `setup.sh` não foi executado           | Seguir os passos do passo 3 para clonar e rodar `bash setup.sh` |
| `DISCORD_GUILD_ID` vazio            | guildId não informado                  | Solicitar ao usuário                                            |
| `gh auth` falhou                    | GitHub CLI não autenticado             | `gh auth login`                                                 |
| `Board não encontrado após criação` | Scope `project` ausente                | `gh auth login --scopes project`                                |
| Clone falhou                        | Token sem permissão de leitura do repo | Verificar GH_TOKEN                                              |

**Se sucesso:**
Informe ao usuário que o projeto está operacional e mostre o resumo do health check.

---

## Modo re-provisionamento de labels

Se apenas as labels precisarem ser recriadas:

```bash
exec("bash", "-c", "LABELS_ONLY=true bash $HOME/.openclaw/workspace/scripts/provision.sh {project} {repo} {channel} {guildId}")
```
