# Chapter 15 — Test & Validation

Environment: subscription `ME-MngEnvMCAP152025-snair-1`, RG `rg-agentic-ai-blueprint-dev`.

## 1. Log Analytics workspace exists

```powershell
az monitor log-analytics workspace show -g rg-agentic-ai-blueprint-dev -n agent-blueprint-dev-law `
  --query "{name:name,sku:sku.name,retention:retentionInDays,state:provisioningState}" -o table
```

Expect `agent-blueprint-dev-law`, `PerGB2018`, retention `30`, `Succeeded`.

## 2. APIM diagnostics route to the workspace

```powershell
$apimId = az apim show -g rg-agentic-ai-blueprint-dev -n apim-agent-blueprint-dev-a5jiq4re --query id -o tsv
az monitor diagnostic-settings show --resource $apimId --name apim-diagnostics `
  --query "{ws:workspaceId,logs:logs[?enabled].category}" -o json
```

Expect `workspaceId` ending in `.../agent-blueprint-dev-law` and `GatewayLogs` enabled.

## 3. Workbook exists

```powershell
az resource list -g rg-agentic-ai-blueprint-dev --resource-type Microsoft.Insights/workbooks `
  --query "[?tags.chapter=='15-observability'].{name:name,display:properties.displayName}" -o table
```

Open it in the portal: **Monitor → Workbooks → Agent Platform Observability**. Tiles render once
telemetry arrives (see step 5).

## 4. Guardrail RAI policy exists

```powershell
az cognitiveservices account rai-policy list -g rg-agentic-ai-blueprint-dev `
  -n agent-blueprint-dev-foundry-std-vlpnxwtn --query "[].name" -o tsv
```

Expect `agent-guardrail-v1` alongside `Microsoft.DefaultV2`.

Confirm the Prompt Shields are blocking:

```powershell
az cognitiveservices account rai-policy show -g rg-agentic-ai-blueprint-dev `
  -n agent-blueprint-dev-foundry-std-vlpnxwtn --policy-name agent-guardrail-v1 `
  --query "properties.contentFilters[?name=='Jailbreak' || name=='Indirect Attack'].{name:name,blocking:blocking,enabled:enabled}" -o table
```

## 5. Gateway logs flow (send traffic first)

Call any APIM-fronted API, then after a few minutes:

```powershell
$ws = az monitor log-analytics workspace show -g rg-agentic-ai-blueprint-dev -n agent-blueprint-dev-law --query customerId -o tsv
az monitor log-analytics query --workspace $ws `
  --analytics-query "ApiManagementGatewayLogs | where TimeGenerated > ago(1h) | summarize count() by ApiId" -o table
```

Expect one row per API that received traffic. (No rows = no traffic yet, or logs still ingesting.)

## 6. Evaluation pipeline runs

```powershell
python -m pip install -r .\infra\chapter-15-observability\requirements.txt
python .\infra\chapter-15-observability\evaluate-agent.py
```

Expect quality scores (Groundedness/Relevance/Coherence/Fluency, 1-5) per row and low safety
severities for the adversarial refusals.

## 7. Red team safety gate

```powershell
python .\infra\chapter-15-observability\red-team-scan.py
```

Expect `Attack success rate: X% (threshold 5.00%)` and `Safety gate passed.` (exit 0). A guarded
target should stay well under threshold; `red-team-report.json` is written for the pipeline.

## Notes / gotchas

- **Path with a space** (`C:\Governed Agentic Framework`): always quote script paths when invoking
  Python, e.g. `python ".\infra\chapter-15-observability\evaluate-agent.py"`.
- **Private data plane**: the evaluation/red-team scripts talk to the private Standard project — run
  them from a host on `agent-blueprint-dev-vnet` or the peered `demovnet` VM.
- **Applying the guardrail policy** to gpt-4o is optional; `Microsoft.DefaultV2` already provides
  Prompt Shields. Use `-ApplyGuardrailToDeployment gpt-4o` only if you want the stricter thresholds.
