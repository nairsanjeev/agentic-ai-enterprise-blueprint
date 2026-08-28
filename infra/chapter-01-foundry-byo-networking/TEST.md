# Chapter 01 — Test & Validation Guide

Use this guide to confirm the Chapter 01 (Foundry BYO networking) deployment is healthy, secure, and reachable.

**Environment**
- Subscription: `ME-MngEnvMCAP152025-snair-1`
- Resource group: `rg-agentic-ai-blueprint-dev`
- Region: `eastus2`

**Key resource names**
| Resource | Name |
|---|---|
| Foundry account | `agent-blueprint-dev-foundry-a5jiq4re` |
| Foundry project | `agent-blueprint-dev-project` |
| Foundry endpoint | `https://agent-blueprint-dev-foundry-a5jiq4re.cognitiveservices.azure.com/` |
| Model deployment | `gpt-4o` (2024-11-20) |
| Storage account | `stnceytbnogaba2` |
| Key Vault | `agent-blueprint-dev-kv-a` |
| VNet | `agent-blueprint-dev-vnet` (192.168.0.0/16) |
| Foundry PE private IPs | cognitiveservices `192.168.1.6`, openai `192.168.1.7`, services.ai `192.168.1.8` |

> Two planes: **control plane** (ARM / portal) is public — you run most `az` checks below from any workstation. **Data plane** (calling the model, building agents) is private — those steps must run from the VM in `demovnet` (peered) or another host inside the VNet.

---

## Part A — Control-plane checks (run from your admin workstation)

### A1. Confirm all resources exist
```powershell
az resource list -g rg-agentic-ai-blueprint-dev --query "sort_by([].{Name:name,Type:type}, &Type)" -o table
```
✅ Expect: Foundry account + project, Key Vault, Storage, VNet, 3 private endpoints (foundry/kv/blob), 5 private DNS zones + links.

### A2. Confirm the security posture (private + Entra-only)
```powershell
az cognitiveservices account show -g rg-agentic-ai-blueprint-dev -n agent-blueprint-dev-foundry-a5jiq4re `
  --query "{Account:name,PublicAccess:properties.publicNetworkAccess,LocalAuth:properties.disableLocalAuth,State:properties.provisioningState}" -o table
```
✅ Expect: `PublicAccess = Disabled`, `LocalAuth = True` (local API keys disabled), `State = Succeeded`.

### A3. Confirm the delegated subnet
```powershell
az network vnet subnet show -g rg-agentic-ai-blueprint-dev --vnet-name agent-blueprint-dev-vnet -n snet-foundry `
  --query "{Subnet:name,Prefix:addressPrefix,Delegation:delegations[0].serviceName}" -o table
```
✅ Expect: `snet-foundry`, `192.168.0.0/24`, delegation `Microsoft.App/environments`.

### A4. Confirm the model is deployed
```powershell
az cognitiveservices account deployment list -g rg-agentic-ai-blueprint-dev -n agent-blueprint-dev-foundry-a5jiq4re `
  --query "[].{Name:name,Model:properties.model.name,Version:properties.model.version,State:properties.provisioningState}" -o table
```
✅ Expect: `gpt-4o` / `gpt-4o` / `2024-11-20` / `Succeeded`.

### A5. Confirm private endpoints are approved & connected
```powershell
az network private-endpoint list -g rg-agentic-ai-blueprint-dev `
  --query "[].{PE:name,State:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" -o table
```
✅ Expect: all three private endpoints `Approved`.

### A6. Confirm your RBAC to build agents
```powershell
az role assignment list `
  --scope "/subscriptions/fb9d6508-5199-40b9-af4f-38befd007c74/resourceGroups/rg-agentic-ai-blueprint-dev/providers/Microsoft.CognitiveServices/accounts/agent-blueprint-dev-foundry-a5jiq4re/projects/agent-blueprint-dev-project" `
  --query "[].{Role:roleDefinitionName,Principal:principalName}" -o table
```
✅ Expect: `Foundry User` for `snair@MngEnvMCAP152025.onmicrosoft.com`.

### A7. Prove public data-plane access is blocked (negative test)
Run this from a machine **outside** the VNet (e.g., your workstation on the public internet):
```powershell
curl.exe -s -o NUL -w "%{http_code}`n" https://agent-blueprint-dev-foundry-a5jiq4re.cognitiveservices.azure.com/
```
✅ Expect: a connection failure or `403` — public access is denied. This is correct.

---

## Part B — Data-plane checks (run from the VM in `demovnet`)

### B1. Verify peering + DNS wiring exists
```powershell
az network vnet peering list -g rg-sanjeevdemovm --vnet-name demovnet --query "[].{Name:name,State:peeringState}" -o table
```
✅ Expect: `peer-to-foundry` = `Connected`.

### B2. Confirm private DNS resolution from the VM
On the **VM**, run:
```powershell
ipconfig /flushdns
nslookup agent-blueprint-dev-foundry-a5jiq4re.cognitiveservices.azure.com
nslookup agent-blueprint-dev-foundry-a5jiq4re.openai.azure.com
```
✅ Expect: private IPs `192.168.1.6` and `192.168.1.7` (NOT a public IP).
❌ If you get a public IP: run `ipconfig /flushdns`; if it persists, the VNet may use custom DNS servers — they need a conditional forwarder to `168.63.129.16`.

### B3. Authenticate and call the model through the private endpoint
On the **VM** (needs Azure CLI and Python with `openai`):
```powershell
az login --tenant MngEnvMCAP152025.onmicrosoft.com
```
```python
# save as test_foundry.py and run: python test_foundry.py
import os
from azure.identity import AzureCliCredential, get_bearer_token_provider
from openai import AzureOpenAI

endpoint = "https://agent-blueprint-dev-foundry-a5jiq4re.openai.azure.com/"
token_provider = get_bearer_token_provider(
    AzureCliCredential(), "https://cognitiveservices.azure.com/.default"
)
client = AzureOpenAI(
    azure_endpoint=endpoint,
    azure_ad_token_provider=token_provider,   # Entra auth — no API keys (local auth is disabled)
    api_version="2024-10-21",
)
resp = client.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": "Reply with exactly: Chapter 01 private path works."}],
)
print(resp.choices[0].message.content)
```
✅ Expect: `Chapter 01 private path works.` — this proves Entra auth + private networking + model deployment all work end to end.
❌ `403 / public network access disabled`: DNS is still resolving to the public IP (see B2).
❌ `401 / PermissionDenied`: your user needs the **Foundry User** role (see A6) and/or `Cognitive Services OpenAI User`.

### B4. Open the Foundry portal from the VM
In the VM's browser, go to `https://ai.azure.com`, open the project `agent-blueprint-dev-project`, and open **Agents**.
✅ Expect: the "Error loading your agents / public access disabled" message is gone and the Agents page loads.

---

## Result checklist
- [ ] A1 resources present
- [ ] A2 public access disabled, local auth disabled
- [ ] A3 subnet delegated to `Microsoft.App/environments`
- [ ] A4 `gpt-4o` Succeeded
- [ ] A5 private endpoints Approved
- [ ] A6 Foundry User role present
- [ ] A7 public access blocked (negative test)
- [ ] B2 VM resolves private IPs
- [ ] B3 model call returns the expected sentence
- [ ] B4 Foundry portal Agents page loads from the VM
