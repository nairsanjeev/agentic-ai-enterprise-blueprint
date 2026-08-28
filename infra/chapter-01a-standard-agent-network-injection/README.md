# Chapter 01a — Standard Agent Setup with Network Injection

This folder upgrades the Chapter 01 private Foundry account into a **Standard Agent Setup with
network injection**, so that **agent tool-call egress flows through your VNet** (`snet-foundry`).

## Why this exists

Chapter 01 makes the Foundry *control/data plane* private, but agents built on it still run their
tool-call egress on the Microsoft-managed network. Calling a VNet-only endpoint (for example an
internal APIM gateway) therefore fails with:

> The host name could not be resolved from the selected network path.

Foundry only injects agent compute into your delegated subnet when the account is a **Standard Agent
Setup** — bring-your-own **Cosmos DB + AI Search + Storage** wired through a **capability host** — and
the account carries a `networkInjections` block. This module provisions exactly that, reusing the
Chapter 01 VNet, subnets, and shared private DNS zones.

## Important constraint

Network injection **cannot be added to an account that already has agents**. This module therefore
stands up a **new** Standard account/project (names suffixed `-std`) alongside Chapter 01. Migrate by
rebuilding agents and tool connections on the Standard project, validate with `TEST.md`, then retire
the old account.

## What it deploys

- Standard Foundry account (with `networkInjections` → `snet-foundry`) + project + optional gpt-4o
- Bring-your-own **Cosmos DB**, **Azure AI Search**, **Storage** (all private, Entra-only)
- Private endpoints + private DNS zones (`documents`, `search`; reuses existing Foundry/blob zones)
- Project connections to the three dependencies (AAD auth)
- Account + project **capability hosts** (kind `Agents`)
- Role assignments the project identity needs to provision and use its containers/indexes

## Prerequisites

- Chapter 01 deployed (its VNet, subnets, and private DNS zones are reused)
- Azure CLI signed in to the blueprint tenant/subscription

## Deploy

Run from the repository root in PowerShell:

```powershell
# 1. Compile check (optional)
az bicep build --file .\infra\chapter-01a-standard-agent-network-injection\main.bicep

# 2. Preview only (no changes)
.\infra\chapter-01a-standard-agent-network-injection\deploy.ps1

# 3. Deploy
.\infra\chapter-01a-standard-agent-network-injection\deploy.ps1 -Execute
```

### Known deployment gotchas (full recovery steps in `TEST.md` Part 0)

- **AI Search capacity:** if the VNet region returns `InsufficientResourcesAvailable`, pass
  `searchLocation=<adjacent region>` (e.g. `eastus`). The VNet private endpoint reaches it cross-region.
- **Account capability host `customerSubnet`:** the account-level capability host must set
  `customerSubnet` to the injected subnet (already in `main.bicep`).
- **Capability hosts are not idempotent:** if a deploy half-completes, don't re-run the template —
  create only the missing **project** capability host via `az rest --method PUT` (see `TEST.md` §0.4).
- **Post-deploy manual steps:** deploy the gpt-4o model, pre-create the `WeatherMCP` connection with the
  Entra audience, create the agent in the portal, then grant the new agent identity `Mcp.Invoke`
  (`TEST.md` §0.6–0.8).

## Validate

Follow `TEST.md` in this folder. It validates network injection, the capability hosts, the private
dependencies, and includes the exact steps to configure MCP/A2A tool connections **without** the
`400 Failed to fetch agentic identity access token` error (correct connection audience).
