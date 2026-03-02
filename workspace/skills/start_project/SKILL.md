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

### 1. Receber e validar os parâmetros

Você precisa de três informações antes de começar:

| Parâmetro | Exemplo                              | Observação                     |
| --------- | ------------------------------------ | ------------------------------ |
| `project` | `quemresolve`                        | slug sem espaços, lowercase    |
| `repo`    | `barba-software/quemresolve-backend` | formato `owner/repo`           |
| `channel` | `quemresolvebackend`                 | nome do canal Discord, sem `#` |

Se algum estiver faltando, pergunte ao usuário antes de continuar.
Normalize o `channel`: remova o `#` caso o usuário tenha passado com ele.

O script é idempotente, então mesmo que o projeto já exista, ele pode ser reexecutado sem causar erros — apenas confirme os parâmetros e siga para o próximo passo.

### 2. Criar o canal Discord

Valide se o canal `channel` ja existe, caso não exista crie o canal de texto `channel` no servidor Discord do projeto. Se o canal já existir, apenas confirme que é o canal correto para este projeto.

Após criar (ou confirmar que já existe), poste a seguinte mensagem de boas-vindas no canal:

```
👋 Bem-vindo ao projeto **{project}**!

📦 Repositório: https://github.com/{repo}
🤖 Squad: Product · Developer · Reviewer · Lead
🔗 Board: será criado automaticamente pelo provision

A squad está sendo configurada. Em instantes estaremos operacionais.
```

### 3. Executar o script de provisionamento

```
exec("$HOME/.openclaw/workspace/scripts/provision.sh", "{project}", "{repo}", "{channel}")
```

Aguarde a conclusão. O script é idempotente — seguro para reexecutar.

### 4. Avaliar o resultado

**Se o script falhar:**

- Mostre a saída de erro completa ao usuário
- Informe qual passo falhou (labels, board, agentes, crons)
- Não poste mensagem de sucesso no Discord
- Sugira: `health_check.sh {project}` para diagnóstico

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
