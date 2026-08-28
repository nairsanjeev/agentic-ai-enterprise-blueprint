# Chapter 01 — Test & Validation Guide

Use this guide to confirm the Chapter 01 (Foundry BYO networking) deployment is healthy, secure, and reachable.

**Environment** — this repo stores no subscription or tenant identifiers. Fill in your own values.

Set these once per session; every control-plane command below reuses them:

```powershell
$rg  = 'rg-agentic-ai-blueprint-dev'   # your resource group
$dep = 'chapter-01-dev'                # deployment name created by deploy.ps1

# Read the actual resource names from the deployment outputs.
$foundry = az deployment group show -g $rg -n $dep --query 'properties.outputs.foundryAccountName.value' -o tsv
$project = az deployment group show -g $rg -n $dep --query 'properties.outputs.foundryProjectName.value' -o tsv
$vnet    = az deployment group show -g $rg -n $dep --query 'properties.outputs.vnetName.value' -o tsv
$storage = az deployment group show -g $rg -n $dep --query 'properties.outputs.storageAccountName.value' -o tsv
$kv      = az deployment group show -g $rg -n $dep --query 'properties.outputs.keyVaultName.value' -o tsv
$subId   = az account show --query id -o tsv
```

**Key resources**
| Resource | Value |
|---|---|
| Foundry account | `$foundry` |
| Foundry project | `$project` |
| Foundry endpoint | `https://$foundry.cognitiveservices.azure.com/` |
| Model deployment | `gpt-4o` (2024-11-20) |
| Storage account | `$storage` |
| Key Vault | `$kv` |
| VNet | `$vnet` (192.168.0.0/16 by default) |

> Two planes: **control plane** (ARM / portal) is public — you run most `az` checks below from any workstation. **Data plane** (calling the model, building agents) is private — those steps must run from a VM inside the platform VNet or a peered admin VNet.

---

## Part A — Control-plane checks (run from your admin workstation)

### A1. Confirm all resources exist
```powershell
az resource list -g $rg --query "sort_by([].{Name:name,Type:type}, &Type)" -o table
```
✅ Expect: Foundry account + project, Key Vault, Storage, VNet, 3 private endpoints (foundry/kv/blob), 5 private DNS zones + links.

### A2. Confirm the security posture (private + Entra-only)
```powershell
az cognitiveservices account show -g $rg -n $foundry `
  --query "{Account:name,PublicAccess:properties.publicNetworkAccess,LocalAuth:properties.disableLocalAuth,State:properties.provisioningState}" -o table
```
✅ Expect: `PublicAccess = Disabled`, `LocalAuth = True` (local API keys disabled), `State = Succeeded`.

### A3. Confirm the delegated subnet
```powershell
az network vnet subnet show -g $rg --vnet-name $vnet -n snet-foundry `
  --query "{Subnet:name,Prefix:addressPrefix,Delegation:delegations[0].serviceName}" -o table
```
✅ Expect: `snet-foundry`, `192.168.0.0/24`, delegation `Microsoft.App/environments`.

### A4. Confirm the model is deployed
```powershell
az cognitiveservices account deployment list -g $rg -n $foundry `
  --query "[].{Name:name,Model:properties.model.name,Version:properties.model.version,State:properties.provisioningState}" -o table
```
✅ Expect: `gpt-4o` / `gpt-4o` / `2024-11-20` / `Succeeded`.

### A5. Confirm private endpoints are approved & connected
```powershell
az network private-endpoint list -g $rg `
  --query "[].{PE:name,State:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" -o table
```
✅ Expect: all three private endpoints `Approved`.

### A6. Confirm your RBAC to build agents
```powershell
az role assignment list `
  --scope "/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$foundry/projects/$project" `
  --query "[].{Role:roleDefinitionName,Principal:principalName}" -o table
```
✅ Expect: `Foundry User` for your signed-in user.

### A7. Prove public data-plane access is blocked (negative test)
Run this from a machine **outside** the VNet (e.g., your workstation on the public internet):
```powershell
curl.exe -s -o NUL -w "%{http_code}`n" "https://$foundry.cognitiveservices.azure.com/"
```
✅ Expect: a connection failure or `403` — public access is denied. This is correct.

---

## Part B — Data-plane checks (run from a host inside the VNet)

Run these from a VM or jumpbox in the platform VNet, or in a peered admin VNet whose DNS resolves the
private endpoints. Replace `<admin-rg>`, `<admin-vnet>`, and `<foundry-account>` with your values.

### B1. Verify peering + DNS wiring exists
```powershell
az network vnet peering list -g <admin-rg> --vnet-name <admin-vnet> --query "[].{Name:name,State:peeringState}" -o table
```
✅ Expect: the peering to the platform VNet shows `Connected`.

### B2. Confirm private DNS resolution from the VM
On the **VM**, run:
```powershell
ipconfig /flushdns
nslookup <foundry-account>.cognitiveservices.azure.com
nslookup <foundry-account>.openai.azure.com
```
✅ Expect: private IPs `192.168.1.6` and `192.168.1.7` (NOT a public IP).
❌ If you get a public IP: run `ipconfig /flushdns`; if it persists, the VNet may use custom DNS servers — they need a conditional forwarder to `168.63.129.16`.

### B3. Authenticate and call the model through the private endpoint
On the **VM** (needs Azure CLI and Python with `openai`):
```powershell
az login   # add --tenant <tenant> to pin a specific tenant
```
```python
# save as test_foundry.py and run: python test_foundry.py
import os
from azure.identity import AzureCliCredential, get_bearer_token_provider
from openai import AzureOpenAI

endpoint = "https://<foundry-account>.openai.azure.com/"
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
In the VM's browser, go to `https://ai.azure.com`, open your project (the `foundryProjectName` output), and open **Agents**.
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
