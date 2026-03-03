---
name: "start_project"
description: "Inicia um novo projeto dentro do sistema OpenClaw, criando toda a estrutura necessária, estado inicial e integrações externas."
---

# START_PROJECT

**Responsável:** Lead Global
**Permissão:** role=lead-global
**Ferramentas:** `exec`, Discord channel tool

---

## Workflow

> [!IMPORTANT]
> Execute todos os passos em ordem, sem pular nenhum sempre, e sempre poste o resultado de cada passo para o usuário.

### 1. Receber e validar os parâmetros

Você precisa de quatro informações antes de começar:

- **project** (nome curto do projeto)
- **repo** (owner/nome-do-repo no GitHub)
- **channel** (nome do canal principal no Discord)
- **guildId** (ID numérico do servidor Discord)

> [!IMPORTANT]
> Verifique se a variável `DISCORD_BOT_TOKEN` está configurada no ambiente do host OpenClaw antes de executar o script. Sem ela, crons e vínculos de canais falharão.

Se algum estiver faltando, pergunte ao usuário antes de continuar.
Normalize o `channel`: remova o `#` caso o usuário tenha passado com ele.

**IMPORTANTE (Prevenção de Timeout):**
Assim que validar os parâmetros, poste IMEDIATAMENTE a primeira mensagem no canal (Passo 2) avisando que o provisionamento começou. Isso evita o erro de "Unknown Interaction" no Discord.

O script é idempotente, então mesmo que o projeto já exista, ele pode ser reexecutado sem causar erros — apenas confirme os parâmetros e siga para o próximo passo.

### 2. Criar o canal Discord e Threads

Siga esta ordem exata para evitar erros de permissão:

1.  **Criar Canal:** Use a ferramenta `create_channel` para criar o canal de texto `{channel}` (se ainda não existir) no servidor `{guildId}`.
2.  **Criar Threads:** Dentro do NOVO canal `{channel}`, use a ferramenta `create_thread` para criar as seguintes threads públicas:
    -   `squad` — Para comunicação técnica.
    -   `lead` — Para gestão e alertas.
3.  **Postar Mensagem:** No canal PRINCIPAL `{channel}` (não nas threads), poste a mensagem de boas-vindas:

```
👋 Bem-vindo ao projeto **{project}**!

📦 Repositório: https://github.com/{repo}
🤖 Squad: Product · Developer · Reviewer · Lead
🧵 Canais: #squad (técnico) | #lead (gestão)
🔗 Board: será criado automaticamente pelo provision

A squad está sendo configurada. Em instantes estaremos operacionais.
```

### 3. Executar o script de provisionamento

```javascript
const output = exec("$HOME/.openclaw/workspace/scripts/provision.sh", "{project}", "{repo}", "{channel}", "{guildId}");
// Importante: Poste o log completo do provision para o usuário revisar.
message(channel, "LOG DE PROVISIONAMENTO:\n```\n" + output + "\n```");
```

Aguarde a conclusão. O script é idempotente — seguro para reexecutar.

### 4. Avaliar o resultado

**Se o script falhar:**

- Analise o "Doctor Check" no início do log.
- Verifique se o `openclaw` foi encontrado e se o `DISCORD_BOT_TOKEN` estava presente.
- Informe qual passo falhou (labels, board, agentes, crons)
- Sugira: `health_check.sh {project}` para diagnóstico

---

## Solução de Problemas (Troubleshooting)

| Sintoma                      | Causa Provável                  | Ação do Agente                       |
| ---------------------------- | ------------------------------- | ------------------------------------ |
| Canal não criado             | Permissão ou `guildId` inválido | Valide o ID e convite do Bot         |
| Crons não aparecem           | `DISCORD_BOT_TOKEN` ausente     | Peça ao usuário para checar a env    |
| `openclaw` não encontrado    | Path não configurado no host    | Reporte o erro de Doctor ao usuário  |
| "Unknown Interaction"        | Timeout do Discord              | Reduza o delay entre mensagens       |

**Se o script tiver sucesso:**

- Poste no canal `#{channel}`:

```
✅ Projeto **{project}** provisionado com sucesso!

🤖 Agentes ativos:
  • {project}-product   — interpreta demandas
  • {project}-developer — implementa issues
  • {project}-reviewer  — revisa PRs
  • {project}-lead      — supervisiona e reporta

📋 GitHub Board: {project} Board
🏷️ Labels criadas: inbox · in_progress · review · blocked · done

Para criar uma tarefa, basta escrever aqui no canal.
O Product Agent irá interpretar e formalizar a Issue automaticamente.
```

### 5. Registrar no relatório global

Após sucesso, informe ao usuário:

- Nome do projeto criado
- Canal Discord: `#{channel}`
- Repositório: `{repo}`
- Comando para verificar saúde: `$HOME/.openclaw/workspace/scripts/health_check.sh {project}`

---

## Erros comuns

| Erro                         | Causa                           | Solução                              |
| ---------------------------- | ------------------------------- | ------------------------------------ |
| `gh auth` falhou             | GitHub CLI não autenticado      | `gh auth login`                      |
| `openclaw agents add` falhou | Agente já existe com mesmo nome | Idempotente — ignorar                |
| Board não encontrado         | Owner sem permissão de Projects | Verificar permissões do token GitHub |
| Canal Discord já existe      | Projeto sendo re-provisionado   | Normal — seguir em frente            |
