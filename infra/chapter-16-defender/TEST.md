# Chapter 16 — Test and Demo Validation

## 1. Defender for AI is enabled

```powershell
az security pricing show --name AI `
  --query "{tier:pricingTier,evidence:extensions[?name=='AIPromptEvidence'].isEnabled | [0],purview:extensions[?name=='AIPromptSharingWithPurview'].isEnabled | [0]}" -o table
```

Expect `Standard`, `True`, and `True`.

## 2. Chapter 15 telemetry dependency is healthy

```powershell
az monitor log-analytics workspace show -g rg-agentic-ai-blueprint-dev `
  -n agent-blueprint-dev-law --query "{name:name,state:provisioningState}" -o table
```

Expect `Succeeded`.

## 3. Create and exercise the portal agent

```powershell
python .\infra\chapter-16-defender\create-portal-demo-agent.py --run-demo
```

Expect the three connection targets to resolve, an agent version to be created, and a
`chapter-16-demo-report.json` file. The governed travel scenario should show policy, weather, and
packing evidence. The injection scenario should refuse, remain governed, or be blocked by the model
content filter.

## 4. Inspect in Microsoft Foundry

Open **Agents → GovernedTravelSecurityDemo**. Confirm its latest version has two MCP tools and one A2A
tool, then open **Tracing** and inspect the generated runs.

## 5. Query custom scenario spans

After several minutes, query the Application Insights Logs blade:

```kql
dependencies
| where timestamp > ago(1h)
| where operation_Name has "agent-demo-scenario"
| project timestamp, operation_Name, duration, success, customDimensions
| order by timestamp desc
```

If no rows appear, confirm `APPLICATIONINSIGHTS_CONNECTION_STRING` was set before running the demo.

## 6. Review security posture

Open **Defender for Cloud → Workload protections → AI workloads** and review inventory and
recommendations. Use the Foundry injection run as trace evidence; do not expect every test prompt to
create a Defender alert because alert creation depends on Microsoft detection confidence.