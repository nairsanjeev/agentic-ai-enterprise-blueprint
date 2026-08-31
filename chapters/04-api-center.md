# Chapter 04 — Create Azure API Center

## Objective

Create an **Azure API Center** as the centralized registry for all MCP servers, skills, APIs, and agent tools across the enterprise. API Center complements the AI Gateway (APIM) by providing design-time governance, discovery, and a developer portal.

By the end of this chapter, you will have:
- An Azure API Center instance linked to APIM
- MCP servers registered and discoverable (including the one from Chapter 02)
- Sample skills registered from agentskills.io
- A developer portal for API and tool discovery

---

## Architecture Context: The Enterprise Catalog for AI

### Where This Fits

API Center is the **design-time registry** that makes the runtime gateway (APIM) discoverable. While APIM governs traffic at runtime, API Center tells developers what's available and how to use it.

```
┌─────────────────────────────────────────────────────────────┐
│                  Developer Experience                         │
│                                                             │
│  "What MCP tools exist?"  "What agents can I delegate to?"  │
│  "What skills are available for my use case?"               │
└──────────────────────┬──────────────────────────────────────┘
                       │ Discovers via
┌──────────────────────▼──────────────────────────────────────┐
│           Azure API Center (This Chapter)                    │
│                                                             │
│  ┌────────────┐  ┌────────────┐  ┌────────────────────┐    │
│  │ MCP Server │  │   Agent    │  │   Skill / Plugin   │    │
│  │ Registry   │  │  Registry  │  │    Registry        │    │
│  └────────────┘  └────────────┘  └────────────────────┘    │
│  ┌────────────┐  ┌────────────┐  ┌────────────────────┐    │
│  │ Governance │  │  Linting   │  │  Conformance       │    │
│  │  Metadata  │  │   Rules    │  │   Scoring          │    │
│  └────────────┘  └────────────┘  └────────────────────┘    │
└──────────────────────┬──────────────────────────────────────┘
                       │ Linked to
┌──────────────────────▼──────────────────────────────────────┐
│           AI Gateway (APIM) — Runtime Governance             │
└─────────────────────────────────────────────────────────────┘
```

### What You Will Achieve

- A **single catalog** where every MCP tool, agent, and skill in the organization is registered
- **Governance metadata** (owner, SLA, data classification, version) for every registered asset
- **APIM integration** that auto-syncs runtime APIs into the catalog
- **Developer discoverability** — developers find tools by capability, not by knowing internal team names

### Benefits of This Approach

| Benefit | Description |
|---------|-------------|
| **Eliminate Duplication** | Developers search before building — find existing tools instead of recreating them |
| **Governance at Scale** | Linting rules and conformance scores ensure all registered assets meet quality standards |
| **Accelerate Composition** | Agents can dynamically discover available tools at runtime via API Center queries |
| **Visibility** | Administrators see the complete landscape of AI capabilities across the organization |
| **Lifecycle Management** | Track API versions, deprecations, and migrations in one place |

---

## Prerequisites

- Chapters 02-03 completed
- Azure CLI authenticated
- APIM instance from Chapter 02 operational

---

## Part 1: Understanding Azure API Center

### What is Azure API Center?

Azure API Center provides a **centralized location** for managing your organization's entire API inventory — regardless of API type, lifecycle stage, or deployment location. It is the **design-time governance** companion to APIM's **runtime governance**.

### How API Center Complements APIM

| Capability | APIM (Runtime) | API Center (Design-time) |
|-----------|----------------|--------------------------|
| API gateway & proxy | ✅ | ❌ |
| Rate limiting & throttling | ✅ | ❌ |
| MCP server exposure | ✅ | ❌ |
| API inventory & catalog | Limited | ✅ Full |
| API governance & linting | ❌ | ✅ |
| MCP server registry (all sources) | APIM-hosted only | ✅ All sources |
| Skill & plugin registry | ❌ | ✅ |
| Developer portal for discovery | ✅ (runtime) | ✅ (catalog) |
| API definition analysis | ❌ | ✅ |
| Cross-platform API tracking | ❌ | ✅ |

### Key Benefits for the Internet of Agents

1. **MCP Server Registry** — Register and discover MCP servers from APIM and external sources in one place
2. **Skill Discovery** — Register skills and plugins for agent consumption
3. **Governance** — Enforce API definition quality through linting and analysis
4. **Developer Self-Service** — Developers find tools and APIs without asking anyone
5. **Synchronized with APIM** — APIs and MCP servers automatically sync between APIM and API Center

---

## Part 2: Create Azure API Center

### Step 1: Create the Instance

```bash
RESOURCE_GROUP="rg-internet-of-agents"
LOCATION="eastus2"
API_CENTER_NAME="apic-agents-platform"

# Create API Center (Standard plan for enterprise features)
az apic create \
  --resource-group $RESOURCE_GROUP \
  --name $API_CENTER_NAME \
  --location $LOCATION
```

> **Cost Tip**: If your API Center is linked to an eligible APIM instance (Standard, Standard v2, Premium, or Premium v2), the Standard plan is available at no extra cost.

### Step 2: Link API Center to APIM

Linking synchronizes APIs and MCP servers between APIM and API Center automatically.

```bash
APIM_RESOURCE_ID=$(az apim show \
  --resource-group $RESOURCE_GROUP \
  --name "apim-agents-gateway" \
  --query id -o tsv)

# Link APIM to API Center
az apic service link create \
  --resource-group $RESOURCE_GROUP \
  --service-name $API_CENTER_NAME \
  --link-name "apim-link" \
  --linked-resource-id $APIM_RESOURCE_ID
```

After linking, all APIs and MCP servers from APIM are automatically visible in API Center.

---

## Part 2a: Tested deployment runbook (current CLI)

> **Reproducible IaC:** this chapter now ships Bicep + deploy script at
> [`infra/chapter-04-api-center/`](../infra/chapter-04-api-center/README.md) (API Center, managed
> identity, live APIM link, governance metadata, and RBAC). The steps below are the equivalent CLI
> walkthrough and the manual portal actions that can't be expressed in ARM.

> The `az apic` extension has changed since the commands above were written. In the current extension
> there is **no** `az apic service link` / `integration` / `portal` / `skill` / `mcp-server` subcommand.
> APIs and MCP servers are pulled in with **`az apic import-from-apim`**, which requires a
> **user-assigned managed identity** on the API Center with reader access to APIM. This is the exact,
> verified sequence for this environment.

```powershell
$r    = 'rg-agentic-ai-blueprint-dev'
$apic = 'apic-agent-blueprint-dev'
$apim = 'apim-agent-blueprint-dev-a5jiq4re'

# 1. Create the API Center (Standard plan; API Center is not in every region — eastus works)
az extension add --name apic-extension
az apic create -g $r -n $apic -l eastus

# 2. Create a user-assigned identity and give it reader on APIM
$uami   = az identity create -g $r -n id-apic-agent-blueprint -l eastus -o json | ConvertFrom-Json
$apimId = az apim show -g $r -n $apim --query id -o tsv
az role assignment create --assignee-object-id $uami.principalId --assignee-principal-type ServicePrincipal `
  --role "API Management Service Reader Role" --scope $apimId

# 3. Attach the identity to the API Center service (PATCH — no CLI flag for this yet)
$svc  = az apic show -g $r -n $apic --query id -o tsv
$body = "{""identity"":{""type"":""UserAssigned"",""userAssignedIdentities"":{""$($uami.id)"":{}}}}"
$f=New-TemporaryFile; [IO.File]::WriteAllText($f.FullName,$body,(New-Object System.Text.UTF8Encoding($false)))
az rest --method PATCH --url "https://management.azure.com$svc`?api-version=2024-06-01-preview" `
  --headers 'Content-Type=application/json' --body "@$($f.FullName)"; Remove-Item $f.FullName

# 4. Import every APIM API + MCP server into the catalog
az apic import-from-apim -g $r --service-name $apic --apim-name $apim --apim-apis '*'

# 5. Verify — the MCP server registers with kind 'mcp'
az apic api list -g $r --service-name $apic --query "[].{name:title,kind:kind}" -o table
```

Expected catalog after import: **City Weather MCP Server** (`mcp`), **Packing Advisor A2A Backend**,
**City Weather API**, **Echo API**, **A2A Well-Known Card** (plus the default `swagger-petstore` sample).

### Custom metadata (governance)

`az apic metadata create` requires the schema as **inline JSON** (the `--schema` flag does not expand
`@file`), so run these from **bash** (or use the portal) to avoid PowerShell quoting issues:

```bash
az apic metadata create -g $r --service-name $apic --metadata-name owning-team \
  --schema '{"type":"string","title":"Owning Team","enum":["travel","hr","finance","engineering","platform"]}' \
  --assignments '[{entity:api,required:false,deprecated:false}]'
az apic metadata create -g $r --service-name $apic --metadata-name data-classification \
  --schema '{"type":"string","title":"Data Classification","enum":["public","internal","confidential","restricted"]}' \
  --assignments '[{entity:api,required:false,deprecated:false}]'
az apic metadata create -g $r --service-name $apic --metadata-name agent-protocol \
  --schema '{"type":"string","title":"Agent Protocol","enum":["mcp","a2a","rest","graphql"]}' \
  --assignments '[{entity:api,required:false,deprecated:false}]'
```

### Developer portal (managed portal)

The API Center **managed portal** at
`https://apic-agent-blueprint-dev.portal.eastus.azure-apicenter.ms` is enabled and wired for sign-in
through the **Azure portal** (no full CLI yet). The Entra app registration for portal sign-in is
automatable:

```powershell
$portalUrl = 'https://apic-agent-blueprint-dev.portal.eastus.azure-apicenter.ms'
$appId = az ad app create --display-name "API Center Portal - apic-agent-blueprint-dev" --sign-in-audience AzureADMyOrg --query appId -o tsv
$objId = az ad app show --id $appId --query id -o tsv
$spa = "{""spa"":{""redirectUris"":[""$portalUrl""]}}"
$f=New-TemporaryFile; [IO.File]::WriteAllText($f.FullName,$spa,(New-Object System.Text.UTF8Encoding($false)))
az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/$objId" --headers 'Content-Type=application/json' --body "@$($f.FullName)"; Remove-Item $f.FullName
Write-Host "Portal sign-in app clientId: $appId"
```

Then finish in the Azure portal:

1. Open API Center `apic-agent-blueprint-dev` → **API Center portal** (left nav).
2. Under **Portal settings → Identity provider**, add **Microsoft Entra ID** and paste the **clientId**
  from the app above (`<portal-app-client-id>`) and your tenant ID.
3. Grant the portal app delegated permission to the API Center service (the portal prompts for admin
   consent the first time).
4. Assign each developer **Azure API Center Data Reader** on the API Center (done for the lab user):
   ```powershell
   $apicId = az apic show -g rg-agentic-ai-blueprint-dev -n apic-agent-blueprint-dev --query id -o tsv
   az role assignment create --assignee <developer-object-id> --role "Azure API Center Data Reader" --scope $apicId
   ```
5. Browse the portal URL, sign in, and confirm the imported MCP server and APIs are discoverable.

Validation steps are in
[`infra/chapter-04-api-center/TEST.md`](../infra/chapter-04-api-center/TEST.md).

---

## Part 3: Register MCP Servers

### Register the MCP Server from Chapter 01

The MCP server created in Chapter 01 (enterprise-tools) should auto-sync from APIM. Verify in the portal:

1. Navigate to API Center in the [Azure portal](https://portal.azure.com)
2. Go to **MCP Servers**
3. Verify `enterprise-tools` appears with its tools:
   - `lookup-employee`
   - `search-policies`
   - `create-ticket`

### Register an External MCP Server

For MCP servers hosted outside APIM:

```bash
# Register an external MCP server
az apic mcp-server create \
  --resource-group $RESOURCE_GROUP \
  --service-name $API_CENTER_NAME \
  --mcp-server-name "external-data-tools" \
  --title "External Data Analytics Tools" \
  --description "MCP server for data analytics operations hosted on Azure Functions" \
  --url "https://func-data-tools.azurewebsites.net/mcp"
```

### MCP Server Discovery for Developers

Developers can discover MCP servers through:

1. **API Center Portal** — Web-based browsing and search
2. **VS Code Extension** — Azure API Center extension for VS Code
3. **CLI** — `az apic mcp-server list`

```bash
# List all registered MCP servers
az apic mcp-server list \
  --resource-group $RESOURCE_GROUP \
  --service-name $API_CENTER_NAME \
  --output table
```

---

## Part 4: Register Skills

Skills are reusable agent capabilities that can be discovered and used by AI agents. They extend agents with specialized functionality.

### Step 1: Browse Available Skills

Visit [agentskills.io](https://agentskills.io/home) to explore available skills. Example skills include:
- **Web Search** — Search the internet for current information
- **Code Execution** — Execute code in a sandboxed environment
- **Document Analysis** — Extract and analyze document content
- **Calendar Management** — Manage calendar events and scheduling

### Step 2: Register Skills in API Center

```bash
# Register a custom skill
az apic skill create \
  --resource-group $RESOURCE_GROUP \
  --service-name $API_CENTER_NAME \
  --skill-name "document-analyzer" \
  --title "Document Analyzer" \
  --description "Analyzes documents for key information extraction, summarization, and classification" \
  --version "1.0" \
  --tags "documents,analysis,extraction"

# Register another skill
az apic skill create \
  --resource-group $RESOURCE_GROUP \
  --service-name $API_CENTER_NAME \
  --skill-name "expense-processor" \
  --title "Expense Report Processor" \
  --description "Processes expense reports, validates against policy, and submits for approval" \
  --version "1.0" \
  --tags "expenses,finance,approval"
```

### Step 3: Register Skills via Portal

For a richer experience, use the Azure portal:

1. Navigate to API Center → **Skills**
2. Select **+ Register Skill**
3. Provide:
   - **Name**: The skill identifier
   - **Description**: What the skill does (used for agent discovery)
   - **Version**: Semantic version
   - **Endpoint**: The skill's API endpoint
   - **OpenAPI Definition**: Upload the skill's API specification
   - **Tags**: Categories for discovery

---

## Part 4a: Private Skill Catalog (tested runbook)

This is the concrete, end-to-end setup that makes organization-scoped skills discoverable in the
Foundry portal, based on
[Create a private skill catalog in Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/private-skill-catalog).

> **Important limitation — read first.** The Foundry **Skills API** (author / attach-to-toolbox /
> download) **does not support private networking**. On a network-injected Standard account with
> `publicNetworkAccess = Disabled` (Chapter 01a), you can still **discover** catalog skills in
> **Build → Skills**, but you cannot *consume* them through the Skills API. To actually run a skill,
> either **bundle it into a hosted agent** (direct injection of the `SKILL.md`, no Skills API at
> runtime) or use a **separate public project** for the Skills API. The catalog itself (API Center) is
> discovery-only and works regardless of the Foundry account's network posture.

### Step 1: Author the skill

A skill is a `SKILL.md` file following the [Agent Skills](https://agentskills.io) format — YAML front
matter (`name`, `description`, both **unquoted**) plus a Markdown body that becomes the injected
instructions. This repo ships a sample at
[`skills/travel-packing-guidelines/SKILL.md`](../skills/travel-packing-guidelines/SKILL.md). Commit it
to a Git repository so API Center can reference it by **Source URL**.

### Step 2: Create the API Center

```powershell
az extension add --name apic-extension
az apic create -g rg-agentic-ai-blueprint-dev -n apic-agent-blueprint-dev -l eastus
```

### Step 3: Register the skill as a catalog asset (portal)

Skill-asset registration is a portal action:

1. In the [Azure portal](https://portal.azure.com), open the API Center `apic-agent-blueprint-dev`.
2. Under **Inventory** → **Assets**, select **+ Register an asset** → **Skill**.
3. Provide the skill's **title** (`Travel Packing Guidelines`), **summary**, **description**,
   **lifecycle stage**, and the **Source URL** of the Git repo folder holding `SKILL.md`.
4. Under **Allowed tools**, select **+ Add tool** and choose the APIs/MCP servers from your API
   inventory the skill may reach (this is the governance boundary — a skill can only use what you
   approve here).
5. Select **Create**. To keep the catalog in sync with source, integrate the Git repo
   ([Synchronize API assets from a Git repo](https://learn.microsoft.com/en-us/azure/api-center/synchronize-assets-git)).

### Step 4: Grant developers discovery access (RBAC)

Developers need at least **Azure API Center Data Reader** on the API Center to see the catalog in
Foundry:

```powershell
$apicId = az apic show -g rg-agentic-ai-blueprint-dev -n apic-agent-blueprint-dev --query id -o tsv
az role assignment create --assignee <developer-object-id> --role "Azure API Center Data Reader" --scope $apicId
```

> Role assignments can take up to 24 hours to propagate.

### Step 5: Discover the catalog in Foundry

1. In the Foundry portal, open your project.
2. Go to **Build** → **Skills**.
3. Search/filter for your private catalog by the API Center name (`apic-agent-blueprint-dev`).
4. Select the `Travel Packing Guidelines` skill and review its summary, source, compatibility, and
   allowed tools.

### Step 6: Use the skill

Because the Skills API can't run on the private account, use **direct injection** in a hosted agent:

1. Download the skill content (`SKILL.md`) from the catalog source.
2. Place it under your hosted-agent project as `skills/travel-packing-guidelines/SKILL.md`.
3. The agent loads every `skills/*/SKILL.md` as extra instructions at session start (no Skills API
   needed at runtime). See
   [Use skills in a hosted agent](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/skills#use-skills-in-a-hosted-agent).

Validation steps are in
[`infra/chapter-04-api-center/TEST.md`](../infra/chapter-04-api-center/TEST.md).

---

## Part 5: Register APIs

### Step 1: Register the Travel Agent A2A API

```bash
# Register the A2A agent API from Chapter 02
az apic api create \
  --resource-group $RESOURCE_GROUP \
  --service-name $API_CENTER_NAME \
  --api-id "travel-agent-a2a" \
  --title "Enterprise Travel Agent (A2A)" \
  --description "A2A-compliant travel booking and policy compliance agent" \
  --type "a2a" \
  --custom-properties '{"team": "travel-services", "environment": "production"}'

# Add a version
az apic api version create \
  --resource-group $RESOURCE_GROUP \
  --service-name $API_CENTER_NAME \
  --api-id "travel-agent-a2a" \
  --version-id "v1" \
  --title "v1.0" \
  --lifecycle-stage "production"
```

### Step 2: Define Custom Metadata

Create custom metadata properties to categorize and govern your APIs:

```bash
# Create metadata for team ownership
az apic metadata create \
  --resource-group $RESOURCE_GROUP \
  --service-name $API_CENTER_NAME \
  --metadata-name "owning-team" \
  --title "Owning Team" \
  --schema '{"type": "string", "enum": ["travel", "hr", "finance", "engineering"]}'

# Create metadata for data classification
az apic metadata create \
  --resource-group $RESOURCE_GROUP \
  --service-name $API_CENTER_NAME \
  --metadata-name "data-classification" \
  --title "Data Classification" \
  --schema '{"type": "string", "enum": ["public", "internal", "confidential", "restricted"]}'

# Create metadata for agent compatibility
az apic metadata create \
  --resource-group $RESOURCE_GROUP \
  --service-name $API_CENTER_NAME \
  --metadata-name "agent-protocol" \
  --title "Agent Protocol" \
  --schema '{"type": "string", "enum": ["mcp", "a2a", "rest", "graphql"]}'
```

---

## Part 6: Set Up the API Center Portal

Deploy the developer-facing portal for self-service discovery.

### Step 1: Enable the Portal

```bash
# Configure the API Center portal
az apic portal create \
  --resource-group $RESOURCE_GROUP \
  --service-name $API_CENTER_NAME \
  --title "Enterprise AI Platform — Tool & Agent Catalog" \
  --description "Discover and consume agents, MCP tools, skills, and APIs"
```

### Step 2: Configure Portal Access

1. In the Azure portal → API Center → **Portal**
2. Configure **Entra ID authentication** for the portal
3. Set up **role-based access**:
   - **API Center Reader** — Can browse and discover
   - **API Center Contributor** — Can register new APIs and tools
   - **API Center Admin** — Full management access

### Step 3: Portal Features

The API Center portal provides:

- **Search & Browse** — Full-text search across all registered assets
- **MCP Server Registry** — Browse MCP servers with connection details
- **Skill Catalog** — Discover skills with descriptions and examples
- **API Details** — View definitions, versions, deployments, and environments
- **Try-It Experience** — Test APIs directly from the portal
- **Connection Snippets** — Copy-paste configuration for MCP clients

---

## Part 7: Enable API Governance

### Step 1: Configure API Linting

Set up automated API definition analysis:

```bash
# Enable managed API analysis (linting)
az apic api-analysis create \
  --resource-group $RESOURCE_GROUP \
  --service-name $API_CENTER_NAME \
  --analysis-name "style-check" \
  --ruleset "microsoft-api-guidelines"
```

### Step 2: API Governance Dashboard

In the Azure portal → API Center → **Governance**:

- View compliance scores across all registered APIs
- Identify APIs missing required metadata
- Track API definition quality over time
- Enforce naming conventions and versioning standards

---

## Part 8: VS Code Integration

### Install the Azure API Center Extension

Developers can discover and use APIs directly from VS Code:

1. Install the **Azure API Center** extension for VS Code
2. Sign in with your Azure account
3. Browse the API Center catalog from the sidebar
4. For MCP servers, the extension can generate `mcp.json` configuration

### Generate MCP Client Configuration

From VS Code, developers can:
1. Browse to an MCP server in the API Center
2. Click **"Copy MCP Configuration"**
3. Paste into their agent's MCP client configuration

```json
{
  "mcpServers": {
    "enterprise-tools": {
      "url": "https://apim-agents-gateway.azure-api.net/mcp/enterprise-tools/mcp",
      "headers": {
        "Authorization": "Bearer <token>"
      }
    }
  }
}
```

---

## Summary

| Component | Status |
|-----------|--------|
| Azure API Center created | ✅ |
| Linked to APIM for auto-sync | ✅ |
| MCP servers registered and discoverable | ✅ |
| Skills registered | ✅ |
| APIs registered with custom metadata | ✅ |
| Developer portal deployed | ✅ |
| API governance (linting) configured | ✅ |

---

## References

- [Azure API Center Overview](https://learn.microsoft.com/en-us/azure/api-center/overview)
- [Register and Discover MCP Servers](https://learn.microsoft.com/en-us/azure/api-center/register-discover-mcp-server)
- [Register and Discover Skills](https://learn.microsoft.com/en-us/azure/api-center/register-discover-skills)
- [Set Up API Center Portal](https://learn.microsoft.com/en-us/azure/api-center/set-up-api-center-portal)
- [Synchronize APIM and API Center](https://learn.microsoft.com/en-us/azure/api-center/synchronize-api-management-apis)

---

## Next Steps

Proceed to [Chapter 05 — Build a React Discovery UI](./05-react-discovery-ui.md)
