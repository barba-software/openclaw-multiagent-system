# Avaliação: Convex como Substituto do state.json

## Resumo Executivo

O Convex é uma excelente opção para substituir o state.json no OpenClaw.
A migração vale a pena a partir do momento em que o sistema tiver 2+ projetos
rodando simultaneamente ou quando a necessidade de dashboard em tempo real
for prioritária. Para o estágio atual (piloto único), o state.json com as
correções aplicadas é suficiente.

---

## O que o Convex oferece vs state.json

| Característica             | state.json (atual)         | Convex                          |
|----------------------------|----------------------------|---------------------------------|
| Persistência               | Arquivo em disco           | Cloud, replicado, com backup    |
| Concorrência               | flock (processo único)     | Transações ACID nativas         |
| Queries                    | jq (shell)                 | TypeScript tipado               |
| Tempo real                 | ❌                         | ✅ Reactive queries + WebSocket |
| Dashboard                  | audit.log manual           | ✅ Dashboard automático         |
| Multi-projeto              | Pastas isoladas            | Tabelas compartilhadas, isoladas por projectId |
| Schema                     | Validação manual (jq)      | ✅ Schema TypeScript obrigatório |
| Histórico / audit          | audit.log append-only      | ✅ Histórico de mutations nativo |
| Custo                      | $0                         | Free tier generoso, pago acima  |
| Complexidade de setup      | Zero                       | npm install + deploy            |
| Funciona offline/local     | ✅                         | ❌ Requer conectividade         |

---

## Modelo de Dados no Convex

```typescript
// convex/schema.ts
import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({

  projects: defineTable({
    name: v.string(),
    repo: v.string(),
    discordChannelId: v.string(),
    status: v.union(v.literal("active"), v.literal("paused"), v.literal("archived")),
    createdAt: v.string(),
  }).index("by_name", ["name"]),

  agents: defineTable({
    projectId: v.id("projects"),
    name: v.string(),          // "developer-1", "developer-2", etc.
    role: v.union(
      v.literal("developer"),
      v.literal("reviewer"),
      v.literal("product"),
      v.literal("lead")
    ),
    capacity: v.number(),
  }).index("by_project", ["projectId"]),

  issues: defineTable({
    projectId: v.id("projects"),
    issueNumber: v.string(),
    status: v.union(
      v.literal("inbox"),
      v.literal("in_progress"),
      v.literal("review"),
      v.literal("approved"),
      v.literal("blocked"),
      v.literal("done")
    ),
    assignedAgentId: v.optional(v.id("agents")),
    metadata: v.optional(v.string()),
    updatedAt: v.string(),
    createdAt: v.string(),
  })
    .index("by_project", ["projectId"])
    .index("by_project_status", ["projectId", "status"])
    .index("by_project_issue", ["projectId", "issueNumber"]),

  auditLog: defineTable({
    projectId: v.id("projects"),
    issueNumber: v.string(),
    event: v.string(),
    action: v.string(),
    status: v.string(),
    detail: v.optional(v.string()),
    timestamp: v.string(),
  }).index("by_project", ["projectId"]),

});
```

---

## Mutations equivalentes ao state_engine.sh

```typescript
// convex/stateEngine.ts
import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

// Equivalente a: state_engine.sh <project> <repo> <issue> issue_created
export const issueCreated = mutation({
  args: { projectName: v.string(), issueNumber: v.string() },
  handler: async (ctx, args) => {
    const project = await ctx.db
      .query("projects")
      .withIndex("by_name", q => q.eq("name", args.projectName))
      .first();
    if (!project) throw new Error(`Projeto ${args.projectName} não encontrado`);

    const productAgent = await ctx.db
      .query("agents")
      .withIndex("by_project", q => q.eq("projectId", project._id))
      .filter(q => q.eq(q.field("role"), "product"))
      .first();

    await ctx.db.insert("issues", {
      projectId: project._id,
      issueNumber: args.issueNumber,
      status: "inbox",
      assignedAgentId: productAgent?._id,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });

    await ctx.db.insert("auditLog", {
      projectId: project._id,
      issueNumber: args.issueNumber,
      event: "issue_created",
      action: "update_issue",
      status: "OK",
      timestamp: new Date().toISOString(),
    });
  },
});

// Equivalente a: auto_assign — com transação atômica (sem race condition)
export const autoAssign = mutation({
  args: { projectName: v.string(), issueNumber: v.string() },
  handler: async (ctx, args) => {
    const project = await ctx.db
      .query("projects")
      .withIndex("by_name", q => q.eq("name", args.projectName))
      .first();
    if (!project) throw new Error("Projeto não encontrado");

    // Buscar todos os developers do projeto
    const developers = await ctx.db
      .query("agents")
      .withIndex("by_project", q => q.eq("projectId", project._id))
      .filter(q => q.eq(q.field("role"), "developer"))
      .collect();

    // Contar issues ativas por developer
    const loads = await Promise.all(developers.map(async dev => {
      const activeCount = await ctx.db
        .query("issues")
        .withIndex("by_project_status", q =>
          q.eq("projectId", project._id).eq("status", "in_progress")
        )
        .filter(q => q.eq(q.field("assignedAgentId"), dev._id))
        .collect();
      return { dev, load: activeCount.length };
    }));

    // Selecionar developer disponível com menor carga
    const available = loads
      .filter(({ dev, load }) => load < dev.capacity)
      .sort((a, b) => a.load - b.load)[0];

    if (!available) throw new Error("Nenhum developer disponível");

    // Atualizar issue — operação atômica
    const issue = await ctx.db
      .query("issues")
      .withIndex("by_project_issue", q =>
        q.eq("projectId", project._id).eq("issueNumber", args.issueNumber)
      )
      .first();
    if (!issue) throw new Error(`Issue ${args.issueNumber} não encontrada`);

    await ctx.db.patch(issue._id, {
      status: "in_progress",
      assignedAgentId: available.dev._id,
      updatedAt: new Date().toISOString(),
    });

    await ctx.db.insert("auditLog", {
      projectId: project._id,
      issueNumber: args.issueNumber,
      event: "auto_assign",
      action: "assign_by_capacity",
      status: "OK",
      detail: `developer=${available.dev.name}`,
      timestamp: new Date().toISOString(),
    });

    return available.dev.name;
  },
});

// Equivalente a: pr_merged — com release_capacity atômica
export const prMerged = mutation({
  args: { projectName: v.string(), issueNumber: v.string() },
  handler: async (ctx, args) => {
    const project = await ctx.db
      .query("projects")
      .withIndex("by_name", q => q.eq("name", args.projectName))
      .first();
    if (!project) throw new Error("Projeto não encontrado");

    const issue = await ctx.db
      .query("issues")
      .withIndex("by_project_issue", q =>
        q.eq("projectId", project._id).eq("issueNumber", args.issueNumber)
      )
      .first();
    if (!issue) throw new Error("Issue não encontrada");

    // Atualizar status para done — release_capacity é implícita
    // (a query de carga usa status=in_progress, não há lista separada)
    await ctx.db.patch(issue._id, {
      status: "done",
      updatedAt: new Date().toISOString(),
    });

    await ctx.db.insert("auditLog", {
      projectId: project._id,
      issueNumber: args.issueNumber,
      event: "pr_merged",
      action: "release_capacity_and_done",
      status: "OK",
      timestamp: new Date().toISOString(),
    });
  },
});
```

> **Nota:** No Convex, o problema do `release_capacity` simplesmente não existe.
> A "capacidade" é calculada via query em tempo real — não há lista `active_issues`
> para manter sincronizada. Isso elimina toda uma classe de bugs.

---

## Integração com o state_engine.sh existente

A migração pode ser **incremental** — o state_engine.sh pode chamar a API
do Convex como um segundo destino de escrita, mantendo o state.json como
fallback enquanto o Convex é validado:

```bash
# No state_engine.sh, após write_state():
# Sincronizar para Convex (opcional, não bloqueia se falhar)
if command -v curl &>/dev/null && [ -n "${CONVEX_URL:-}" ]; then
  curl -s -X POST "$CONVEX_URL/api/mutation" \
    -H "Content-Type: application/json" \
    -d "{\"path\": \"stateEngine:$EVENT\", \"args\": {\"projectName\": \"$PROJECT\", \"issueNumber\": \"$ISSUE\"}}" \
    || echo "⚠ Convex sync falhou (state.json preservado)"
fi
```

---

## Recomendação de Migração

### Fase 1 — Agora (sem Convex)
Usar state.json com as correções aplicadas nesta versão.
Suficiente para 1-2 projetos piloto.

### Fase 2 — Quando tiver 3+ projetos ou precisar de dashboard
1. `npm create convex@latest` no workspace
2. Criar schema conforme acima
3. Implementar mutations para cada evento
4. Adicionar chamada ao Convex como escrita dupla no state_engine.sh
5. Validar por 2 semanas em paralelo
6. Remover state.json após confiança estabelecida

### Fase 3 — Convex como fonte única
- Remover state.json e flock
- Reescrever state_engine.sh como thin wrapper de chamadas HTTP ao Convex
- Dashboard automático via Convex Dashboard ou frontend React com useQuery
