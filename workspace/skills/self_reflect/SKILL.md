---
name: "self_reflect"
description: "Registra lições aprendidas após erros, bloqueios ou situações inesperadas."
---

# SKILL: SELF_REFLECT

**Responsável:** Developer Agent, Reviewer Agent
**Permissão:** role=developer, role=reviewer
**Trigger:** Após resolver um erro, bloqueio ou comportamento inesperado durante a execução

---

## Objetivo

Registrar lições estruturadas em `LESSONS.md` para que ciclos futuros (sessões isoladas) partam de uma base de conhecimento acumulada. O histórico sobrevive entre sessões; o contexto não — LESSONS.md resolve esse gap.

## Quando invocar

- Após sair de um bloqueio inesperado
- Quando uma etapa falhou e exigiu abordagem alternativa
- Quando a abordagem inicial estava errada e foi corrigida
- Quando identificar padrão que, se ignorado, vai se repetir em ciclos futuros

## Protocolo

### 1. Localizar LESSONS.md

Developer:

```bash
LESSONS="$HOME/.openclaw/workspace/projects/{project}/agents/developer/LESSONS.md"
```

Reviewer:

```bash
LESSONS="$HOME/.openclaw/workspace/projects/{project}/agents/reviewer/LESSONS.md"
```

### 2. Preparar entrada estruturada

Use o formato exato:

```
## [YYYY-MM-DD] {contexto em 1 linha}
**Erro/Situação:** {o que aconteceu}
**Causa:** {por que aconteceu}
**Lição:** {regra acionável — inicie com verbo no imperativo}
**Ação corretiva aplicada:** {o que foi feito para resolver}
```

Exemplo real:

```
## [2026-03-05] git push falhou com "src refspec not found"
**Erro/Situação:** `git push` retornou refspec error após `git checkout -b`
**Causa:** branch criada fora do diretório correto do repositório
**Lição:** Sempre executar `pwd` antes de criar branch — garantir que está em `~/.openclaw/workspace/projects/{project}/repo`
**Ação corretiva aplicada:** cd corrigido, branch recriada, push bem-sucedido
```

### 3. Inserir entrada e rotacionar (máx. 30)

```bash
TODAY=$(date +%Y-%m-%d)

# Inserir nova entrada após o cabeçalho (linha 5)
{
  head -5 "$LESSONS"
  printf '\n## [%s] {contexto}\n**Erro/Situação:** {situação}\n**Causa:** {causa}\n**Lição:** {lição}\n**Ação corretiva aplicada:** {ação}\n' "$TODAY"
  tail -n +6 "$LESSONS"
} > /tmp/_lessons_tmp && mv /tmp/_lessons_tmp "$LESSONS"

# Rotacionar — manter apenas as 30 mais recentes
COUNT=$(grep -c "^## \[" "$LESSONS" 2>/dev/null || echo 0)
if [ "$COUNT" -gt 30 ]; then
  KEEP=$(( COUNT - 30 ))
  HEADER=$(head -5 "$LESSONS")
  BODY=$(awk '/^## \[/{n++} n>'"$KEEP"'{print}' "$LESSONS")
  printf '%s\n\n%s\n' "$HEADER" "$BODY" > "$LESSONS"
fi
```

### 4. Confirmar

Ao finalizar, imprima:

```
✅ SELF_REFLECT: lição registrada — [{contexto}]
```

---

## Regras

- ❌ Nunca registrar lição vaga como "algo deu errado" ou "houve um problema"
- ✅ A **Lição** deve ser uma regra acionável (ex: "Sempre verificar X antes de Y")
- ✅ Prefira registrar agora, mesmo imperfeitamente, a não registrar
- ✅ Lead lê LESSONS.md no standup diário e promove padrões recorrentes ao SOUL.md
