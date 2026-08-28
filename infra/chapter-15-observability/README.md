# Chapter 15 — Observability, Evaluation, and Guardrails

Reproducible IaC and scripts for the Chapter 15 telemetry, evaluation, and safety controls.

## What `main.bicep` deploys (management plane)

- **Log Analytics workspace** `agent-blueprint-dev-law` — a dedicated, queryable workspace for gateway
  logs and dashboards (the existing App Insights points at an auto-created *managed* workspace).
- **APIM diagnostic settings** `apim-diagnostics` on the Chapter 02 gateway — streams `GatewayLogs`
  and `AllMetrics` into the workspace so `ApiManagementGatewayLogs` is populated.
- **Azure Workbook** *Agent Platform Observability* — the KQL dashboards: agent success rate, model
  cost, tool latency (from Application Insights `customEvents`), and gateway throughput/errors (from
  the workspace).
- **Custom RAI content-filter policy** `agent-guardrail-v1` on the Standard Foundry account —
  `Microsoft.DefaultV2` baseline plus **blocking Prompt Shields** (jailbreak + indirect/document
  attacks). It is *created only*; it is not applied to any deployment automatically.

## What is NOT redeployed

The template references the existing **Application Insights** and **gpt-4o** deployment as `existing`
and does not modify them. Two optional, opt-in actions are handled by `deploy.ps1`:

- `-MigrateAppInsights` — repoints App Insights at the new workspace so agent telemetry sits next to
  the gateway logs (touches an existing resource).
- `-ApplyGuardrailToDeployment gpt-4o` — applies `agent-guardrail-v1` to a model deployment (this
  redeploys the deployment object).

> gpt-4o already runs the `Microsoft.DefaultV2` filter, which includes Prompt Shields, so applying the
> custom policy is only needed if you want the stricter blocking thresholds.

## Prerequisites

- Chapter 02 deployed (APIM + Application Insights)
- Chapter 01a deployed (Standard Foundry account) for the guardrail policy

## Deploy

```powershell
# Preview only (validate + what-if)
.\infra\chapter-15-observability\deploy.ps1

# Deploy workspace + diagnostics + workbook + guardrail policy
.\infra\chapter-15-observability\deploy.ps1 -Execute

# Optional: consolidate App Insights into the new workspace and apply the stricter policy
.\infra\chapter-15-observability\deploy.ps1 -Execute -MigrateAppInsights -ApplyGuardrailToDeployment gpt-4o
```

## Evaluation and red teaming (data plane — run after `az login`)

```powershell
python -m pip install -r .\infra\chapter-15-observability\requirements.txt

# Quality + safety evaluators
python .\infra\chapter-15-observability\evaluate-agent.py

# Red team scan (CI/CD safety gate — non-zero exit if attack success rate > threshold)
python .\infra\chapter-15-observability\red-team-scan.py
```

Both scripts default to the Standard project endpoint and use `AzureCliCredential`. Override with
`FOUNDRY_PROJECT_ENDPOINT` if needed.

Validate the deployment with [`TEST.md`](./TEST.md).
