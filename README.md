# OpenClaw Multi-Agent Ecosystem

O **OpenClaw Multi-Agent System** é uma arquitetura autônoma de desenvolvimento de software governada por Inteligência Artificial. Ele utiliza múltiplos agentes especializados que cooperam para gerenciar todo o ciclo de vida do desenvolvimento — desde a concepção do produto no Discord até o merge do código no GitHub —, mantendo uma rígida separação de responsabilidades (Triggers, Workflows e Skills) e um motor central de estados (`state-engine`).

## 🧠 Arquitetura de Agentes

O ecossistema é composto por quatro agentes com responsabilidades bem definidas, que assumem a forma de uma squad ágil de alta performance:

- 🎒 **Product Agent:** Interage com os stakeholders vi Discord, ajuda na ideação, analisa riscos corporativos e converte intenções em "GitHub Issues" ricas e estruturadas.
- 💻 **Developer Agent (Alfred):** Absorve as issues designadas a ele, opera no ambiente local (`workspace`), executa o código sob os critérios de aceite e propõe Pull Requests.
- 🕵️ **Reviewer Agent:** Monitora a fila de Pull Requests. Inspeciona o código, avalia a sanidade dos testes e a cobertura dos requisitos. Ele aprova (merge) ou barra (bloqueia) e solicita mudanças.
- 👔 **Lead Agent (Scrum Master):** Atua no cronograma diário montando reportes de Standup diários, avaliando gargalos crônicos (como PRs ou issues paradas) e alertando a equipe de anomalias no fluxo.

## 🔄 Fluxo de Trabalho (Workflow)

Abaixo o diagrama exato de como as entidades se comunicam assincronamente através do `state-engine` e do GitHub, formando o ciclo de vida de uma feature.

```mermaid
sequenceDiagram
    participant User as 👤 Usuário (Discord)
    participant Product as 🎒 Product Agent
    participant GitHub as 🐙 GitHub (Issues/PRs)
    participant StateEngine as ⚙️ State Engine (JSON)
    participant Dev as 💻 Developer Agent
    participant Reviewer as 🕵️ Reviewer Agent
    participant Lead as 👔 Lead Agent

    User->>Product: Solicita nova feature / relata bug (Discord)
    Product->>Product: Avalia riscos e clarifica os dados
    Product->>GitHub: Cria Issue estruturada com Critérios de Aceite
    Product->>StateEngine: Dispara evento "issue_created"
    StateEngine-->>Dev: Atribui Issue formalmente ao agente dev

    Note over Dev: O HEARTBEAT do dev acorda e manda ele ler o AGENTS.md
    Dev->>StateEngine: Verifica qual a sua issue atual (skill EXECUTE_ISSUE)
    Dev->>Dev: Puxa o repo, cria branch, gera e testa o código localmente

    Dev->>GitHub: Abre o Pull Request documentado
    Dev->>StateEngine: Dispara evento "pr_created" (Move ticket pra Review)

    Note over Reviewer: O HEARTBEAT do revisor acorda
    Reviewer->>GitHub: Inspeciona a sanidade do Pull Request
    
    alt Necessita Mudanças
        Reviewer->>GitHub: Solicita mudanças no PR
        Reviewer->>StateEngine: Dispara evento "blocked" (Move ticket pra Blocked)
        StateEngine-->>Lead: Aciona alerta no canal interno
    else Aprovado
        Reviewer->>GitHub: Executa Merge (Squash) do PR
        Reviewer->>StateEngine: Dispara evento "pr_merged" (Move ticket pra Done, liberando DEV)
    end
    
    loop Todo fim do dia e durante o ciclo
        Lead->>StateEngine: Consulta PRs velhos e bloqueios (DAILY_STANDUP / BLOCK_DETECTION)
        Lead->>User: Envia Sumário Diário ao Discord
    end
```

## ✨ Principais Funcionalidades

1. **Separação Abstrata de Arquivos (`De-coupled Architecture`):**
   - `HEARTBEAT.md`: Atua apenas como "Despertador temporal" ou Gatilho. Nenhum comando sensível vive aqui.
   - `AGENTS.md`: Define a "Inteligência" e a lógica humana / processual de cada cargo.
   - `SKILLS.md` & `scripts/*.sh`: Segura a "Força Bruta" e as integrações (Scripts, GH CLI, processamentos JQ, etc), impedindo que o LLM "alucine" comandos.
2. **Motor de Estado Confiável (`state_engine.sh`):**
   - Transita as tarefas no `state.json` do projeto, mantendo os agentes alinhados sobre qual é a pauta real limitando o processamento fantasma, servindo como o Core Source of Truth no lugar de usar APIs voláteis.
3. **Identidade Estrita de Versionamento:**
   - Prevenções para que commits e features não vazem o tracking (ex: Developer assinando os commits como `alfred-ai-developer` em um ambiente clonado apartado).

## 🚀 Como Utilizar e Provisionar

O projeto foi projetado para auto-provisionar as pastas e dependências dos agentes baseado num único script bash que injeta os *fallbacks* (templates padrão de comportamento) de todos os papéis da equipe.

### 1. Requisitos do Servidor / Máquina
Você precisa assegurar a existência instalada e ativa de:
- CLI do GitHub (`gh` autenticado e vinculado a conta e o board).
- Processador de JSON (`jq` via apt/brew).
- Um motor / backend do **OpenClaw** rodando para orquestrar e agendar os heartbeats.
- Uma chave / token para permissões do repo repassados em variável de ambiente.

### 2. Iniciar o Provisionamento (Self-Install Wizard)
Mecanize todo o processo instalando a arquitetura globalmente na sua máquina com um único comando iterativo. 

Esta "Skill de Instalação":
1. Clona/Atualiza a base oficial.
2. Interage no terminal pedindo nome do Projeto, link do Repositório e Canal do Discord.
3. Injeta as Skills em seu diretório e engatilha o `provision.sh` automaticamente.

```bash
curl -sL https://raw.githubusercontent.com/barba-software/openclaw-multiagent-system/main/install.sh | bash
```

*(Alternativamente, para provisionamento manual, você pode dar `git clone` neste repositório, preencher os configs e rodar manualmente `bash workspace/scripts/provision.sh` preenchendo as varáveis).*

### 3. Integração
- Uma vez ligado o webhook / cron cronometrado do `HEARTBEAT.md` no painel do OpenClaw, basta ir ao seu canal do Discord (definido no mapeamento global) e disparar a sua requisição como requerimento em linguagem natural para que o `Product Agent` assuma a liderança.
