# Chapter 02 — Test & Validation Guide (AI Gateway / APIM)

Use this guide to confirm the Chapter 02 APIM AI Gateway is deployed, privately reachable, and routing LLM traffic to the Foundry backend.

**Environment**
- Resource group: `rg-agentic-ai-blueprint-dev`
- APIM instance: `apim-agent-blueprint-dev-a5jiq4re` (Developer tier, **Internal** VNet injection)
- Gateway hostname: `apim-agent-blueprint-dev-a5jiq4re.azure-api.net` (resolves to a **private** IP)
- APIM subnet: `snet-apim` (192.168.2.0/24) in `agent-blueprint-dev-vnet`
- Model backend: Foundry account `agent-blueprint-dev-foundry-a5jiq4re`, model `gpt-4o`
- App Insights: `agent-blueprint-dev-gateway-appi`
- Private DNS zone: `azure-api.net`

> APIM is **Internal** — its gateway has no public IP. All gateway tests (Parts C–E) must run from the VM in `demovnet` (peered) or another host inside the VNet.

---

## Part A — Wait for provisioning to finish

APIM Developer-tier creation with VNet injection takes ~30–45 minutes.
```powershell
az deployment group show -g rg-agentic-ai-blueprint-dev -n chapter-02-dev --query "properties.provisioningState" -o tsv
az apim show -g rg-agentic-ai-blueprint-dev -n apim-agent-blueprint-dev-a5jiq4re --query "provisioningState" -o tsv
```
✅ Proceed only when the deployment is `Succeeded` and APIM is `Succeeded` (not `Activating`/`Running`).

---

## Part B — Control-plane checks (any workstation)

### B1. APIM is Internal with a private IP
```powershell
az apim show -g rg-agentic-ai-blueprint-dev -n apim-agent-blueprint-dev-a5jiq4re `
  --query "{Name:name,Sku:sku.name,VnetType:virtualNetworkType,PrivateIP:privateIpAddresses[0],PublicIP:publicIpAddresses[0]}" -o table
```
✅ Expect: `Sku = Developer`, `VnetType = Internal`, a `PrivateIP` in `192.168.2.x`.

### B2. APIM subnet has the NSG and is not delegated (classic injection)
```powershell
az network vnet subnet show -g rg-agentic-ai-blueprint-dev --vnet-name agent-blueprint-dev-vnet -n snet-apim `
  --query "{Subnet:name,Prefix:addressPrefix,NSG:networkSecurityGroup.id,Delegations:delegations}" -o table
```
✅ Expect: prefix `192.168.2.0/24`, an NSG attached, `Delegations = []`.

### B3. APIM managed identity can reach the model backend
```powershell
$apimId = az apim show -g rg-agentic-ai-blueprint-dev -n apim-agent-blueprint-dev-a5jiq4re --query "identity.principalId" -o tsv
az role assignment list --assignee $apimId `
  --scope "$(az cognitiveservices account show -g rg-agentic-ai-blueprint-dev -n agent-blueprint-dev-foundry-a5jiq4re --query id -o tsv)" `
  --query "[].roleDefinitionName" -o table
```
✅ Expect: `Cognitive Services OpenAI User`.

### B4. Internal DNS records for the gateway exist
```powershell
az network private-dns record-set a list -g rg-agentic-ai-blueprint-dev -z azure-api.net `
  --query "[].{Record:name,IP:aRecords[0].ipv4Address}" -o table
```
✅ Expect: A-records for `apim-agent-blueprint-dev-a5jiq4re` (+ `.developer/.management/.portal/.scm`) all pointing to the APIM private IP.

---

## Part C — Private reachability from the VM

### C1. DNS resolves the gateway to a private IP
On the **VM**:
```powershell
ipconfig /flushdns
nslookup apim-agent-blueprint-dev-a5jiq4re.azure-api.net
```
✅ Expect: the `192.168.2.x` private IP (NOT public).

### C2. Gateway responds (unauthenticated request is rejected = reachable)
On the **VM**:
```powershell
curl.exe -s -o NUL -w "%{http_code}`n" https://apim-agent-blueprint-dev-a5jiq4re.azure-api.net/status-0123456789abcdef
```
✅ Expect: an HTTP status (e.g., `200`/`404`/`401`) — any HTTP response proves the private gateway is reachable. A timeout means peering/DNS/NSG is wrong.

---

## Part D — Expose an API & see it in the gateway (portal)

These are portal steps (APIM API import/MCP export are not available via CLI).

### D1. Import the Foundry model API
1. Portal → your APIM `apim-agent-blueprint-dev-a5jiq4re` → **APIs** → **+ Add API** → **Azure AI Foundry** (or **Azure OpenAI**).
2. Select the Foundry resource `agent-blueprint-dev-foundry-a5jiq4re` and the `gpt-4o` deployment.
3. Set **API URL suffix** to `llm` (gateway path becomes `/llm/...`).
4. Choose **Managed identity** for backend auth (APIM already has the `Cognitive Services OpenAI User` role from B3).
5. Create.
✅ Expect: a new API appears with the chat completions operation.

### D2. Get a subscription key to call the gateway
```powershell
# Use the built-in all-access subscription (or create a product subscription in the portal)
az rest --method post `
  --url "https://management.azure.com$(az apim show -g rg-agentic-ai-blueprint-dev -n apim-agent-blueprint-dev-a5jiq4re --query id -o tsv)/subscriptions/master/listSecrets?api-version=2024-05-01" `
  --query primaryKey -o tsv
```
Copy the key (referred to below as `<APIM_KEY>`).

### D3. See the API/operations exposed
Portal → APIM → **APIs** → open the imported API → **Test** tab shows each operation. This is the gateway surface consumers use.

---

## Part E — Test the GenAI gateway (from the VM)

### E1. Call the model through APIM (single endpoint, APIM key, no LLM key)
On the **VM**, replace `<APIM_KEY>` and run:
```powershell
$body = '{ "messages": [ { "role": "user", "content": "Reply with exactly: Gateway works." } ] }'
curl.exe -s -X POST "https://apim-agent-blueprint-dev-a5jiq4re.azure-api.net/llm/deployments/gpt-4o/chat/completions?api-version=2024-10-21" `
  -H "Ocp-Apim-Subscription-Key: <APIM_KEY>" `
  -H "Content-Type: application/json" `
  -d $body
```
✅ Expect: a JSON chat completion whose content is `Gateway works.` — this proves client → APIM (private) → Foundry (private, managed-identity auth) end to end.
> The exact path (`/llm/...`) depends on the **API URL suffix** you set in D1. Check the operation URL in the portal **Test** tab if unsure.

❌ `401` from APIM: missing/invalid `Ocp-Apim-Subscription-Key`.
❌ `401/403` from backend: APIM identity missing the `Cognitive Services OpenAI User` role (see B3).
❌ Connection timeout: DNS/peering/NSG issue (see C1/C2).

### E2. (Optional) Apply a GenAI policy and re-test
Portal → APIM → your API → **Inbound processing** → add token rate limiting:
```xml
<inbound>
    <base />
    <llm-token-limit counter-key="@(context.Subscription.Id)"
        tokens-per-minute="10000" estimate-prompt-tokens="true"
        remaining-tokens-variable-name="remainingTokens" />
</inbound>
<outbound>
    <base />
    <llm-emit-token-metric namespace="ai-gateway-metrics">
        <dimension name="Subscription" value="@(context.Subscription.Id)" />
        <dimension name="API" value="@(context.Api.Id)" />
    </llm-emit-token-metric>
</outbound>
```
Re-run E1 several times quickly.
✅ Expect: requests succeed until the token budget is exceeded, then `429 Too Many Requests` — confirms GenAI governance is active.

### E3. Confirm telemetry is flowing
Portal → APIM → **APIs** → your API → enable Application Insights logging (points to `agent-blueprint-dev-gateway-appi`), send a few E1 requests, then check the App Insights resource → **Logs**:
```kusto
requests | where timestamp > ago(30m) | order by timestamp desc | take 20
```
✅ Expect: rows for your gateway calls (latency, result code).

---

## Result checklist
- [ ] A APIM + deployment `Succeeded`
- [ ] B1 Internal, private IP in 192.168.2.x
- [ ] B2 subnet has NSG, no delegation
- [ ] B3 APIM identity has `Cognitive Services OpenAI User`
- [ ] B4 gateway A-records present
- [ ] C1 VM resolves gateway to private IP
- [ ] C2 gateway returns an HTTP status from the VM
- [ ] D1 Foundry API imported and visible
- [ ] E1 model call through APIM returns the expected sentence
- [ ] E2 token limit produces 429 when exceeded (optional)
- [ ] E3 telemetry visible in App Insights (optional)
