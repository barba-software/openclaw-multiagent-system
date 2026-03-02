# AGENTS — {MAIN_NAME}

## Intenções do usuário → ação

| O usuário diz                       | Você faz                                                    |
| ----------------------------------- | ----------------------------------------------------------- |
| "quero criar um projeto"            | Coleta `project`, `repo`, `channel` → skill `start_project` |
| "como estão os projetos" / "status" | Skill `cross_project_report`                                |
| "tem algum problema?" / "saúde"     | `exec health_check.sh` para todos os projetos               |
| "pausa o projeto X"                 | Confirma → skill `pause_project`                            |
| "arquiva o projeto X"               | Confirma (irreversível) → skill `archive_project`           |
| "sprint no projeto X"               | Coleta duração + meta → skill `sprint_mode`                 |
| "reprioriza o X"                    | Skill `reprioritize_backlog` no contexto do projeto         |
| demanda de produto / bug            | Redireciona para o canal do projeto                         |
| projeto não especificado            | Pergunta qual — lista os ativos do `registry.json`          |

## Ao iniciar (boot)

1. Ler `$HOME/.openclaw/workspace/registry.json`
2. Para cada projeto ativo: checar `audit.log` por erros recentes e `state.json` por integridade
3. Se tudo OK: aguardar o usuário
4. Se houver anomalia: notificar proativamente antes de qualquer pergunta

## Ao receber uma mensagem ambígua

1. Identificar o projeto ao qual se refere (ou perguntar)
2. Verificar o estado atual daquele projeto no `state.json`
3. Responder com dados reais — nunca inventar status

## Executar skill

```
exec("$HOME/.openclaw/workspace/scripts/provision.sh", ...)   ← via start_project
exec("$HOME/.openclaw/workspace/scripts/health_check.sh", ...) ← diagnóstico
exec("$HOME/.openclaw/workspace/scripts/reconcile.sh", ...)    ← corrigir divergências
```
