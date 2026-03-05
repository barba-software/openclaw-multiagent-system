---
name: "scale_developer"
description: "Adiciona um developer ao projeto após aprovação do usuário. Executado pelo Lead."
---

# SKILL: SCALE_DEVELOPER

**Responsável:** Lead Agent  
**Permissão:** role=lead  
**Trigger:** Developer saturado por 2+ ciclos consecutivos de heartbeat

---

## Quando usar

O Lead usa esta skill quando detecta saturação persistente:
- `developer-1` com `active_issues >= capacity` por 2+ ciclos (15 min cada)
- Contador em `memory/lead/saturation_count.txt` >= 2

**Nunca executar sem confirmação explícita do usuário.**

## Protocolo

### 1. Verificar saturação

```bash
cat ~/.openclaw/workspace/projects/{project}/state.json | jq '
  .agents | to_entries
  | map(select(.value.role == "developer"))
  | map({
      name: .key,
      load: (.value.active_issues | length),
      capacity: .value.capacity,
      saturado: ((.value.active_issues | length) >= .value.capacity)
    })
'
```

### 2. Propor ao usuário na thread lead

```
⚠️ {project}-lead — alerta de capacidade

Problema: developer-1 está com capacity 100% por {N} ciclos consecutivos ({N*15} min).
Issues aguardando atribuição: {lista de issues em inbox ou sem developer}

Sugestão: adicionar developer-2 (capacity=1).

Confirma o escalonamento? (responda "sim" para prosseguir)
```

**Aguardar confirmação. Não executar o script sem ela.**

### 3. Executar após confirmação

```bash
bash ~/.openclaw/workspace/scripts/scale_developer.sh {project} {repo}
```

### 4. Confirmar na thread lead

```
✅ developer-2 adicionado com capacity=1.
O próximo auto_assign distribuirá issues entre developer-1 e developer-2.
```

### 5. Resetar contador

```bash
echo "0" > ~/.openclaw/workspace/projects/{project}/memory/lead/saturation_count.txt
```

---

## Regras

- ❌ Nunca executar scale_developer.sh sem confirmação do usuário
- ❌ Nunca adicionar mais de 1 developer por vez
- ❌ Nunca mudar a capacity de developers existentes
- ✅ Capacity inicial de novos developers é sempre 1
