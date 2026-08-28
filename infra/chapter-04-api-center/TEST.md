# Chapter 04 — Private Skill Catalog: Test & Validation

Validate the private skill catalog (Azure API Center) and the `travel-packing-guidelines` skill.

**Environment**
- Resource group: `rg-agentic-ai-blueprint-dev`
- API Center: `apic-agent-blueprint-dev` (region `eastus`)
- Skill source: [`skills/travel-packing-guidelines/SKILL.md`](../../skills/travel-packing-guidelines/SKILL.md)

> **Limitation:** the Foundry **Skills API** does not support private networking. On the private
> Standard account (`agent-blueprint-dev-foundry-std-vlpnxwtn`, public access disabled) you can
> **discover** catalog skills but not consume them via the Skills API. Runtime use is via **direct
> injection** into a hosted agent, or via a **separate public project**.

---

## A. Catalog infrastructure (control plane)

### A1. API Center exists
```powershell
az apic show -g rg-agentic-ai-blueprint-dev -n apic-agent-blueprint-dev --query "{name:name,location:location,state:provisioningState}" -o table
```
✅ Expect: `Succeeded`.

### A2. Developer has discovery RBAC
```powershell
$apicId = az apic show -g rg-agentic-ai-blueprint-dev -n apic-agent-blueprint-dev --query id -o tsv
az role assignment list --scope $apicId --query "[?roleDefinitionName=='Azure API Center Data Reader'].principalName" -o table
```
✅ Expect: your developer(s) listed. (Propagation can take up to 24h.)

### A3. Skill asset is registered
After registering the skill in the portal (Inventory → Assets → Register an asset → Skill), confirm it
appears:
```powershell
az apic api list -g rg-agentic-ai-blueprint-dev -n apic-agent-blueprint-dev --query "[?kind=='skill' || contains(name,'packing')].{name:name,title:title,kind:kind}" -o table
```
✅ Expect: the `travel-packing-guidelines` / `Travel Packing Guidelines` asset. (If empty, the portal
registration hasn't completed or Git sync hasn't run.)

---

## B. Discovery in Foundry (data plane)

### B1. Catalog appears in Build → Skills
1. Foundry portal → your project → **Build** → **Skills**.
2. Search for `apic-agent-blueprint-dev` or `Travel Packing Guidelines`.

✅ Expect: the skill is listed with its summary, source, and **allowed tools**.
❌ If missing: verify the RBAC role (A2), the correct project, and that the asset is registered (A3).

---

## C. Use the skill (direct injection — works on the private account)

### C1. Bundle the SKILL.md into a hosted agent
```powershell
# From your hosted-agent project root:
New-Item -ItemType Directory -Force -Path .\skills\travel-packing-guidelines | Out-Null
Copy-Item ..\..\skills\travel-packing-guidelines\SKILL.md .\skills\travel-packing-guidelines\SKILL.md
```
The hosted agent loads every `skills/*/SKILL.md` as extra instructions at session start — no Skills API
call, so this works even with public network access disabled.

### C2. Test the behavior
Run the hosted agent and prompt: **"Make me a packing list for Seattle."**

✅ Expect the checklist to follow the skill's guidelines: starts with Documents, grouped sections
(Documents, Clothing, Electronics, Health, Essentials), ≤5 items per section, weather assumption
stated, and a closing entry-requirements reminder.

---

## D. Error-to-fix map

| Symptom | Cause | Fix |
|---|---|---|
| Catalog not visible in Foundry | Missing `Azure API Center Data Reader`, wrong project, or RBAC not propagated | Assign role (A2); wait up to 24h |
| Skill missing from catalog | Asset not registered or Git sync pending | Register in portal (A3); enable Git sync |
| Skills API 403 / not reachable on `-std` account | Skills API doesn't support private networking | Use direct injection (C) or a public project |
| Skill runs but can't reach a resource | Resource not in the skill's **Allowed tools** | Add the API/MCP server to Allowed tools in API Center |
| `invalid_payload` creating a skill version | `name`/`description` quoted or invalid name | Use unquoted YAML; name `^[a-z0-9]([a-z0-9\-]*[a-z0-9])?$` |

---

## E. Full catalog (APIM import + developer portal)

### E1. The API Center imported the APIM APIs + MCP server
```powershell
az apic api list -g rg-agentic-ai-blueprint-dev --service-name apic-agent-blueprint-dev --query "[].{title:title,kind:kind}" -o table
```
✅ Expect: **City Weather MCP Server** (`mcp`), **Packing Advisor A2A Backend**, **City Weather API**,
**Echo API**, **A2A Well-Known Card** (plus the default `swagger-petstore`).
❌ If only `swagger-petstore`: the import didn't run — check the UAMI (E2) and re-run
`az apic import-from-apim ... --apim-apis '*'`.

### E2. API Center has the user-assigned identity with APIM reader
```powershell
$svc = az apic show -g rg-agentic-ai-blueprint-dev -n apic-agent-blueprint-dev --query id -o tsv
az rest --method GET --url "https://management.azure.com$svc`?api-version=2024-06-01-preview" --query "identity.type" -o tsv
az role assignment list --assignee 29597cd6-b836-4024-b1cf-bad09db9280d --query "[?contains(roleDefinitionName,'API Management')].roleDefinitionName" -o table
```
✅ Expect: `UserAssigned`, and `API Management Service Reader Role`.

### E3. Developer portal sign-in app exists
```powershell
az ad app list --display-name "API Center Portal - apic-agent-blueprint-dev" --query "[].{appId:appId,spa:spa.redirectUris}" -o json
```
✅ Expect: the app with SPA redirect `https://apic-agent-blueprint-dev.portal.eastus.azure-apicenter.ms`.

### E4. Portal discovery (after enabling in the Azure portal)
1. Enable the managed portal and wire the sign-in app (chapter Part 2a → *Developer portal*).
2. Browse `https://apic-agent-blueprint-dev.portal.eastus.azure-apicenter.ms`, sign in.

✅ Expect: the imported MCP server and APIs are searchable and their details/versions render.
❌ If sign-in fails: confirm the app's SPA redirect matches the portal URL, the identity provider is
configured with the correct clientId/tenant, and you hold **Azure API Center Data Reader**.

### E5. Governance metadata (optional)
```powershell
az apic metadata list -g rg-agentic-ai-blueprint-dev --service-name apic-agent-blueprint-dev --query "[].name" -o table
```
✅ Expect (if created): `owning-team`, `data-classification`, `agent-protocol`. Create them from **bash**
(inline JSON) or the portal — see chapter Part 2a.

### E6. Typed assets show under Agents / Skills / MCP servers
The APIM import registers everything as `rest`/`mcp`. The Agent and Skill are registered as typed
assets so they land under the right portal tabs:
```powershell
$svc = az apic show -g rg-agentic-ai-blueprint-dev -n apic-agent-blueprint-dev --query id -o tsv
az rest --method GET --url "https://management.azure.com$svc/workspaces/default/apis?api-version=2024-06-01-preview" --query "value[].{title:properties.title,kind:properties.kind}" -o table
```
✅ Expect: `City Weather MCP Server` = `mcp`, `Packing Advisor Agent` = `agent`,
`Travel Packing Guidelines` = `skill` (plus the imported `rest` APIs).
❌ If the Agent/Skill are missing or show as `rest`: register them with `kind: agent` / `kind: skill`
via `az rest PUT .../workspaces/default/apis/<name>?api-version=2024-06-01-preview`, or deploy
`main.bicep` with `deploySampleAssets=true`. In the portal, the **Agents** and **Skills** tabs filter
by these kinds.

> **Definition tab shows "No definition available" for agent/skill assets.** Registering with
> `kind: agent`/`kind: skill` via the classic `apis` API creates a discoverable metadata asset (and the
> **Documentation** tab carries the `externalDocumentation` link), but the classic
> `versions/definitions` API is rejected for these kinds — they use a **dedicated preview data-plane
> API**. To render a full definition, register via the portal: **Inventory → Assets → + Register an
> asset → Agent/Skill**, and set the **Source URL** (the `SKILL.md` Git path for the skill, the A2A
> agent card URL for the agent).
