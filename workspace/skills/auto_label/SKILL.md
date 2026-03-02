---
name: "auto_label"
description: "Analisa o conteúdo de issues para aplicar labels técnicas automáticas."
---

# SKILL: AUTO_LABEL

**Responsável:** Product Agent
**Permissão:** role=product
**Trigger:** Durante a criação ou triagem de issues

---

## Protocolo

Esta skill deve ser usada para enriquecer a Issue com labels técnicas baseadas no conteúdo da descrição.

### 1. Selecionar Labels Técnicas
Analise o corpo da issue e aplique labels adicionais se houver correspondência:

- Menção a "vulnerabilidade", "vaza", "ataque", "auth" → `security`
- Menção a "lento", "delay", "trava", "otimização" → `performance`
- Menção a "documentação", "readme", "wiki" → `documentation`
- Menção a "teste", "unitário", "cobertura" → `testing`

### 2. Sincronização
Se estiver usando o `create_and_dispatch.sh`, adicione estas labels ao argumento final de labels.

---

## Observação
As labels de **Status** (inbox, in_progress, etc) são gerenciadas automaticamente pelo `state_engine.sh`. Não tente alterá-las via esta skill.
