# Chapter 04 — Azure API Center (enterprise catalog)

Turns `chapters/04-api-center.md` into reproducible IaC. Provisions the API Center, links it to the
existing APIM gateway so APIs and MCP servers sync into the catalog, adds governance metadata, and
grants discovery access used by the Foundry private skill catalog and the developer portal.

## What `main.bicep` deploys

- **Azure API Center** `apic-agent-blueprint-dev` with a **user-assigned managed identity**
- Role assignment: the identity gets **API Management Service Reader** on APIM (so sync can read it)
- **APIM link** (`apiSources`) for automatic API + MCP server sync into the catalog
- **Governance metadata** schemas: `owning-team`, `data-classification`, `agent-protocol`
- Role assignment: a principal gets **Azure API Center Data Reader** on the catalog

## Not in the template (can't be expressed in ARM/Bicep)

- **Managed developer portal** enablement and its **Entra app registration** — Entra apps aren't ARM.
  `deploy.ps1 -ConfigurePortalApp` creates the sign-in app; you enable/wire the portal in the Azure
  portal (see below).
- **Skill asset** registration — a portal action per the private-skill-catalog docs.

## Prerequisites

- Chapter 02 deployed (the APIM instance the catalog links to)
- Azure CLI signed in; the `apic-extension` is installed automatically on first use

## Deploy

```powershell
# Preview only
.\infra\chapter-04-api-center\deploy.ps1

# Deploy (also triggers the first APIM import)
.\infra\chapter-04-api-center\deploy.ps1 -Execute

# Deploy and create the developer-portal sign-in Entra app
.\infra\chapter-04-api-center\deploy.ps1 -Execute -ConfigurePortalApp
```

## Enable the developer portal (Azure portal)

Portal URL: `https://apic-agent-blueprint-dev.portal.eastus.azure-apicenter.ms`

1. Azure portal → API Center `apic-agent-blueprint-dev` → **API Center portal**.
2. **Portal settings → Identity provider** → add **Microsoft Entra ID**; paste the sign-in app
   **clientId** (from `-ConfigurePortalApp`) and your tenant ID.
3. Grant admin consent when prompted.
4. Ensure each developer has **Azure API Center Data Reader** (the template grants the deploy user).
5. Browse the portal URL, sign in, and confirm the imported MCP server and APIs are discoverable.

## Validate

Follow [`TEST.md`](./TEST.md) — it validates the imported catalog (APIs + MCP), the identity/RBAC, the
portal sign-in app, and the private skill catalog.

## Note on the chapter's older CLI commands

The chapter text predates the current `az apic` extension, which has **no** `service link`,
`integration`, `portal`, `skill`, or `mcp-server` subcommands. This IaC uses the supported model:
`apiSources` (live link) in Bicep plus `import-from-apim` for the initial populate.
