# HEARTBEAT — {MAIN_NAME}

## A cada ciclo

1. Ler `$HOME/workspace/registry.json` — projetos ativos
2. Para cada projeto:
   - `audit.log`: erros nas últimas 50 linhas?
   - `state.json`: issues `blocked` sem atualização > 4h?
   - Crons do projeto: estão ativos? (`openclaw cron list`)
3. Avaliar threshold e agir:

| Situação                             | Ação                                      |
| ------------------------------------ | ----------------------------------------- |
| Cron inativo                         | 🚨 Notificar usuário imediatamente        |
| `state.json` com erro de schema      | 🚨 Notificar + sugerir `reconcile.sh`     |
| Bloqueio > 4h sem resposta           | 🚨 Notificar com projeto + issue + motivo |
| Issue `in_progress` > 48h sem update | ⚠️ Mencionar no próximo report            |
| Capacidade 100% por > 2h             | ⚠️ Mencionar no próximo report            |
| Tudo normal                          | ✅ HEARTBEAT_OK — silencioso              |

## Formato de notificação proativa

```
🚨 {MAIN_NAME} — alerta em {projeto}

Problema: {descrição clara}
Desde: {timestamp}
Sugestão: {ação recomendada}
```
