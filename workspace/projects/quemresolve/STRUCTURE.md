# STRUCTURE.md

Estrutura de diretórios do projeto Quem Resolve Backend.

## Pastas de Agentes

- `product/` → Product Agent (interpreta demandas, cria Issues)
- `developer/` → Developer Agent (implementa código, cria PRs)
- `reviewer/` → Reviewer Agent (revisa código, aprova PRs)
- `lead/` → Lead Agent (supervisiona, reporta status)

## Arquivos de Configuração

- `PROJECT.md` → Visão geral do projeto
- `AGENTS.md` → Regras e fluxo dos agentes
- `HEARTBEAT_GLOBAL.md` → Protocolo de heartbeat
- `DISCORD.md` → Regras de comunicação Discord
- `GITHUB.md` → Regras de workflow GitHub
- `STRUCTURE.md` → Este arquivo

## Arquivos de Estado

- `state.json` → Estado atual do sistema (issues, agents, capacidade)
- `state.lock` → Lock file (gerado automaticamente)

## Scripts Utilitários (em `/workspace/scripts/`)

- `agent-state.sh` → Gerenciador de estado para multi-agentes
- `provision.sh` → Provisionamento automatizado de novos projetos

## Fluxo de Trabalho

User → Product → Issue GitHub → Developer → PR → Reviewer → Merge → Lead reporta
