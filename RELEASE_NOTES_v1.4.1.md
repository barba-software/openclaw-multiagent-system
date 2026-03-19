# Release Notes — v1.4.1

> Correções de Estabilidade: Rate Limit e Timeouts

## Como criar a tag e release após merge

```bash
git tag -a v1.4.1 -m "v1.4.1 — Correções de Estabilidade: Rate Limit e Timeouts"
git push origin v1.4.1
gh release create v1.4.1 --title "v1.4.1 — Correções de Estabilidade" --notes-file RELEASE_NOTES_v1.4.1.md
```

---

## 🔧 Correções

### ⏱️ Timeout Aumentado para 600s

Crons de agentes agora executam com timeout de 10 minutos (600 segundos), evitando falhas em operações longas como reconcile e review de PRs grandes.

- `workspace/scripts/provision.sh`: adicionado `--timeout-seconds 600` em todas as chamadas `openclaw cron add`

### 💤 Wake Mode: next-heartbeat

Todos os crons agora usam `wake next-heartbeat` em vez de `wake now`, evitando execução imediata em startup e permitindo melhor distribuição de carga entre execuções.

- `workspace/scripts/provision.sh`: adicionado `--wake next-heartbeat` em todas as chamadas `openclaw cron add`

### 🌊 Mitigação de Rate Limit

A combinação de timeout maior e wake mode distribuído reduz significativamente a chance de atingir rate limits da API da NVIDIA.

---

## 📋 Arquivos Modificados

| Arquivo | Mudanças |
|---------|----------|
| `workspace/scripts/provision.sh` | `--timeout-seconds 600` e `--wake next-heartbeat` em todos os crons |

**Full Changelog**: https://github.com/obarbadev/openclaw-multiagent-system/compare/v1.4.0...v1.4.1
