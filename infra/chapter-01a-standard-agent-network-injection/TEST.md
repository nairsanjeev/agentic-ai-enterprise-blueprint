# Chapter 01a — Standard Agent Setup with Network Injection: Test & Validation

Use this guide to confirm the Standard Agent Setup deployed by `main.bicep` is healthy and that
agent **tool-call egress flows through your VNet** (`snet-foundry`), so agents can reach VNet-only
endpoints such as the internal APIM gateway.

It also captures the exact fix for the two errors commonly hit when wiring an agent to an
internal MCP/A2A tool:

1. `Failed to fetch agentic identity access token with status code: 400` — wrong/missing connection **audience**.
2. `The host name could not be resolved from the selected network path` — **no network injection** (this chapter fixes it).

**Environment**
- Subscription: `<subscription-name>`
- Resource group: `rg-agentic-ai-blueprint-dev`
- Region: `eastus2`
- Reused network: `agent-blueprint-dev-vnet` → `snet-foundry` (delegated), `snet-privateendpoints`

Set these once for the commands below:

```powershell
$rg      = 'rg-agentic-ai-blueprint-dev'
# Prefer deployment outputs; fall back to discovering the -std account by tag if the
# ARM deployment reported Failed (a partial capability-host/Search failure still leaves
# the account in place — see Part 0).
$acctName = az deployment group show -g $rg -n chapter-01a-dev --query 'properties.outputs.foundryAccountName.value' -o tsv 2>$null
if (-not $acctName) {
  $acctName = az resource list -g $rg --resource-type Microsoft.CognitiveServices/accounts --query "[?contains(name,'foundry-std')].name | [0]" -o tsv
}
$projName = 'agent-blueprint-dev-project-std'
$acctId   = "/subscriptions/$((az account show --query id -o tsv))/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$acctName"
Write-Host "Account: $acctName`nProject: $projName"
```

---

## Part 0 — Deploy and finish (the actual runbook)

Follow these in order. Steps 0.3–0.5 are the manual recoveries you may hit; 0.6–0.8 always apply.

### 0.1 Deploy the infrastructure
```powershell
.\infra\chapter-01a-standard-agent-network-injection\deploy.ps1 -Execute
```

### 0.2 If Search fails with `InsufficientResourcesAvailable`
The VNet region can be out of Azure AI Search capacity. Re-run pointing Search at an adjacent
region (the VNet private endpoint still reaches it cross-region):
```powershell
.\infra\chapter-01a-standard-agent-network-injection\deploy.ps1 -Execute
# deploy.ps1 forwards searchLocation; or deploy the template directly with:
#   az deployment group create ... --parameters searchLocation=eastus
```

### 0.3 If the account capability host fails with `customerSubnet must match`
The account-level capability host must set `customerSubnet` to the injected subnet. This is already
in `main.bicep`; if you hand-rolled an older version, add `customerSubnet: agentSubnet.id` and redeploy.

### 0.4 If a re-run fails with `existing Capability Host ... cannot create a new Capability Host`
Capability hosts are **not idempotent** — once the account host exists, re-running the full template
conflicts. Do **not** re-run the template. Confirm what already exists:
```powershell
az rest --method GET --url "https://management.azure.com$acctId/capabilityHosts?api-version=2025-06-01" --query "value[].{name:name,state:properties.provisioningState}" -o table
az rest --method GET --url "https://management.azure.com$acctId/projects/$projName/capabilityHosts?api-version=2025-06-01" --query "value[].{name:name,state:properties.provisioningState}" -o table
```
If the **account** host is `Succeeded` but the **project** host is missing, create only the project host:
```powershell
$body='{"properties":{"capabilityHostKind":"Agents","storageConnections":["agent-storage"],"threadStorageConnections":["agent-thread-storage"],"vectorStoreConnections":["agent-vector-store"]}}'
$f=New-TemporaryFile; [System.IO.File]::WriteAllText($f.FullName,$body)
az rest --method PUT --url "https://management.azure.com$acctId/projects/$projName/capabilityHosts/$projName-cap?api-version=2025-06-01" `
  --headers 'Content-Type=application/json' --body "@$($f.FullName)" --query "{name:name,state:properties.provisioningState}" -o json
Remove-Item $f.FullName
```
Then poll until `Succeeded`:
```powershell
az rest --method GET --url "https://management.azure.com$acctId/projects/$projName/capabilityHosts/$projName-cap?api-version=2025-06-01" --query "properties.provisioningState" -o tsv
```

### 0.5 Confirm the project identity has its data-plane roles
The capability host needs these before it can provision containers/indexes (the module creates them,
but verify after a partial deploy):
```powershell
$projMi = az rest --method GET --url "https://management.azure.com$acctId/projects/$projName?api-version=2025-06-01" --query "identity.principalId" -o tsv
az role assignment list --assignee $projMi --all --query "[].roleDefinitionName" -o table
az cosmosdb sql role assignment list --account-name (az resource list -g $rg --resource-type Microsoft.DocumentDB/databaseAccounts --query "[?contains(name,'cosmos')].name | [0]" -o tsv) -g $rg --query "[].principalId" -o table
```
✅ Expect: `Storage Blob Data Owner`, `Cosmos DB Operator`, `Search Service Contributor`,
`Search Index Data Contributor`, and the project MI listed under the Cosmos SQL data-plane role.

### 0.6 Deploy the gpt-4o model on the new account
The deploy script provisions the account with `deployModel=false`; add the model explicitly:
```powershell
az cognitiveservices account deployment create -g $rg -n $acctName `
  --deployment-name gpt-4o --model-name gpt-4o --model-version 2024-11-20 --model-format OpenAI `
  --sku-name GlobalStandard --sku-capacity 30 --query "properties.provisioningState" -o tsv
```

### 0.7 Pre-create the WeatherMCP connection with the correct audience
```powershell
$apiAppId = az ad app list --display-name 'agent-blueprint-apim-agent-tools' --query "[0].appId" -o tsv
$body = "{""properties"":{""category"":""RemoteTool"",""target"":""https://apim-agent-blueprint-dev-a5jiq4re.azure-api.net/mcp/weather/mcp"",""authType"":""AgenticIdentityToken"",""audience"":""api://$apiAppId"",""isSharedToAll"":true,""metadata"":{""type"":""custom_MCP""}}}"
$f=New-TemporaryFile; [System.IO.File]::WriteAllText($f.FullName,$body)
az rest --method PUT --url "https://management.azure.com$acctId/projects/$projName/connections/WeatherMCP?api-version=2025-06-01" `
  --headers 'Content-Type=application/json' --body "@$($f.FullName)" --query "{name:name,audience:properties.audience}" -o json
Remove-Item $f.FullName
```

### 0.8 Create the agent, then grant its NEW agent identity the Mcp.Invoke role
Each project has its **own** agent identity, created on first agent. This is a private data-plane
action — do it in the Foundry portal:
1. Open project **`agent-blueprint-dev-project-std`** → create a prompt agent on **gpt-4o** → attach **WeatherMCP**.

Then grant the new agent identity the app role (find it by name, no portal lookup needed):
```powershell
$agentIdentityId = az ad sp list --filter "displayname eq '$acctName-$projName-AgentIdentity'" --query "[0].id" -o tsv
if (-not $agentIdentityId) { $agentIdentityId = az ad sp list --query "[?contains(displayName,'project-std-AgentIdentity')].id | [0]" -o tsv }
$apiSp     = az ad sp show --id $apiAppId -o json | ConvertFrom-Json
$appRoleId = ($apiSp.appRoles | Where-Object { $_.value -eq 'Mcp.Invoke' -and $_.isEnabled }).id
$assign = @{ principalId = $agentIdentityId; resourceId = $apiSp.id; appRoleId = $appRoleId } | ConvertTo-Json
$f=New-TemporaryFile; [System.IO.File]::WriteAllText($f.FullName,$assign)
az rest --method POST --url "https://graph.microsoft.com/v1.0/servicePrincipals/$agentIdentityId/appRoleAssignments" `
  --headers 'Content-Type=application/json' --body "@$($f.FullName)"
Remove-Item $f.FullName
```

### 0.9 Test
Ask the agent **"what is the weather in seattle"** — expect a normal weather answer.

---

## Part A — Validate the Standard Setup (control plane)

### A1. Network injection is configured on the account
This is the property whose absence caused the "network path" error.
```powershell
az rest --method GET --url "https://management.azure.com$acctId?api-version=2025-06-01" `
  --query "properties.networkInjections" -o json
```
✅ Expect one entry: `scenario = agent`, `subnetArmId` ending in `/subnets/snet-foundry`, `useMicrosoftManagedNetwork = false`.
❌ If `null`: the account is not injected — agents run on the Microsoft-managed network and cannot reach VNet-only endpoints.

### A2. Both capability hosts exist and are Succeeded
```powershell
az rest --method GET --url "https://management.azure.com$acctId/capabilityHosts?api-version=2025-06-01" `
  --query "value[].{name:name,state:properties.provisioningState}" -o table
az rest --method GET --url "https://management.azure.com$acctId/projects/$projName/capabilityHosts?api-version=2025-06-01" `
  --query "value[].{name:name,state:properties.provisioningState,storage:properties.storageConnections,threads:properties.threadStorageConnections,vectors:properties.vectorStoreConnections}" -o json
```
✅ Expect: account host `Succeeded`; project host `Succeeded` with `storageConnections`, `threadStorageConnections`, and `vectorStoreConnections` each populated.

### A3. The three BYO connections are present and AAD-authenticated
```powershell
az rest --method GET --url "https://management.azure.com$acctId/projects/$projName/connections?api-version=2025-06-01" `
  --query "value[].{name:name,category:properties.category,auth:properties.authType}" -o table
```
✅ Expect: `agent-storage` (AzureStorageAccount), `agent-thread-storage` (CosmosDB), `agent-vector-store` (CognitiveSearch) — all `AAD`.

### A4. Dependencies are private (no public access)
```powershell
az cosmosdb show -g $rg -n (az deployment group show -g $rg -n chapter-01a-dev --query 'properties.outputs.cosmosAccountName.value' -o tsv) --query "{public:publicNetworkAccess,localAuth:disableLocalAuth}" -o table
az search service show -g $rg -n (az deployment group show -g $rg -n chapter-01a-dev --query 'properties.outputs.searchServiceName.value' -o tsv) --query "{public:publicNetworkAccess,localAuth:disableLocalAuth}" -o table
az storage account show -g $rg -n (az deployment group show -g $rg -n chapter-01a-dev --query 'properties.outputs.storageAccountName.value' -o tsv) --query "{public:publicNetworkAccess,sharedKey:allowSharedKeyAccess}" -o table
```
✅ Expect: Cosmos/Search `publicNetworkAccess = Disabled` and local auth disabled; Storage `Disabled` + shared key `False`.

### A5. Private endpoints for all four services are Approved
```powershell
az network private-endpoint list -g $rg `
  --query "[?contains(name,'std') || contains(name,'cosmos') || contains(name,'search')].{PE:name,State:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" -o table
```
✅ Expect: Foundry, Cosmos, Search, and Storage private endpoints all `Approved`.

### A6. Private DNS zones for the new dependencies are linked to the VNet
```powershell
foreach ($z in 'privatelink.documents.azure.com','privatelink.search.windows.net') {
  Write-Host "--- $z ---"
  az network private-dns link vnet list -g $rg --zone-name $z --query "[].{link:name,state:virtualNetworkLinkState}" -o table
}
```
✅ Expect: each zone has a link to `agent-blueprint-dev-vnet` in state `Completed`.

---

## Part B — Fix the tool connection audience (the 400 token error)

> This is the step that prevents `Failed to fetch agentic identity access token with status code: 400`.
> The agent identity requests an Entra token for the connection's **audience**. The audience MUST be a
> Microsoft Entra **Application ID URI** (`api://<app-id>`) — **never** the APIM gateway URL, and never `null`.

### B1. Confirm the audience app registration exists
The audience app fronts the APIM MCP/A2A APIs. Capture its Application (client) ID.
```powershell
$apiAppId = az ad app list --display-name 'agent-blueprint-apim-agent-tools' --query "[0].appId" -o tsv
if (-not $apiAppId) { throw 'Audience app not found. Create it per infra/chapter-02a-mcp-a2a/TEST.md section 6.1.1.' }
$audience = "api://$apiAppId"
Write-Host "Audience app id: $apiAppId"
Write-Host "Audience (URI):  $audience"
```

### B2. Grant the Standard project's agent identity the Mcp.Invoke app role
The agent identity exists only after the first agent is created on the Standard project. Create one agent, then:
```powershell
# agentIdentityId = object ID of the project's agent identity service principal
# (Foundry portal > project > Overview > JSON View > agentIdentityId)
$agentIdentityId = '<agentIdentityId>'

$apiSp     = az ad sp show --id $apiAppId -o json | ConvertFrom-Json
$appRoleId = ($apiSp.appRoles | Where-Object { $_.value -eq 'Mcp.Invoke' -and $_.isEnabled }).id

$assignment = @{ principalId = $agentIdentityId; resourceId = $apiSp.id; appRoleId = $appRoleId } | ConvertTo-Json
$f = New-TemporaryFile; [System.IO.File]::WriteAllText($f.FullName, $assignment)
az rest --method POST `
  --url "https://graph.microsoft.com/v1.0/servicePrincipals/$agentIdentityId/appRoleAssignments" `
  --headers 'Content-Type=application/json' --body "@$($f.FullName)"
Remove-Item $f.FullName
```

### B3. Create the MCP/A2A connections with the correct audience
```powershell
$mcpTarget = 'https://apim-agent-blueprint-dev-a5jiq4re.azure-api.net/mcp/weather/mcp'
$a2aTarget = 'https://apim-agent-blueprint-dev-a5jiq4re.azure-api.net/agents/packing-advisor'

azd ai connection create WeatherMCP --kind remote-tool `
  --target $mcpTarget --auth-type agentic-identity --audience $audience

azd ai connection create chapter02a-packing-advisor --kind remote-a2a `
  --target $a2aTarget --auth-type agentic-identity --audience $audience
```

### B4. VERIFY the audience is set (catches the null/wrong-audience bug)
Portal-created or `azd`-created connections sometimes land with `audience = null` or the APIM URL.
This check is mandatory before testing.
```powershell
foreach ($c in 'WeatherMCP','chapter02a-packing-advisor') {
  $a = az rest --method GET --url "https://management.azure.com$acctId/connections/$c?api-version=2025-06-01" --query "properties.audience" -o tsv
  Write-Host ("{0,-30} audience = {1}" -f $c, ($a ? $a : '<null>'))
}
```
✅ Expect: both print `api://<app-id>`.
❌ If either is `<null>` or an `https://...azure-api.net...` URL, fix it in B5.

### B5. Repair a wrong/null connection audience in place
```powershell
$connName = 'WeatherMCP'   # or chapter02a-packing-advisor
$category = 'RemoteTool'   # use 'RemoteA2A' for the A2A connection
$target   = $mcpTarget     # use $a2aTarget for the A2A connection

$body = "{""properties"":{""category"":""$category"",""target"":""$target"",""authType"":""AgenticIdentityToken"",""audience"":""$audience""}}"
$f = New-TemporaryFile; [System.IO.File]::WriteAllText($f.FullName, $body)
az rest --method PUT --url "https://management.azure.com$acctId/connections/$connName?api-version=2025-06-01" `
  --headers 'Content-Type=application/json' --body "@$($f.FullName)" `
  --query "{name:name,audience:properties.audience}" -o json
Remove-Item $f.FullName
```
✅ Expect: the returned `audience` is `api://<app-id>`.

### B6. Enforce the token at APIM
Apply `validate-azure-ad-token` to the weather MCP server and the A2A API, using the same audience.
See `infra/chapter-02a-mcp-a2a/TEST.md` §6.1.2. The `<audience>` element must read `api://<app-id>`.

---

## Part C — End-to-end test (data plane)

### C1. Create/rebuild the agent on the Standard project
In the Foundry portal, open the **Standard** project (`agent-blueprint-dev-project-std`), create a prompt
agent on `gpt-4o`, and attach the `WeatherMCP` tool.

### C2. Ask the agent a question that calls the tool
Prompt: **"what is the weather in seattle"**

✅ Expect: a normal answer (tool invoked successfully).

Error-to-cause map if it still fails:

| Error text | Root cause | Fix |
|---|---|---|
| `Failed to fetch agentic identity access token ... 400` | Connection `audience` is null or the APIM URL | Part B4/B5 — set `audience = api://<app-id>` |
| `... ARA request failed with status BadRequest` | Agent identity lacks the `Mcp.Invoke` app role | Part B2 |
| `host name could not be resolved from the selected network path` | Account has no `networkInjections` (agent not in VNet) | Deploy this chapter (A1) and rebuild the agent |
| `401`/`403` from APIM after token mints | APIM `validate-azure-ad-token` audience mismatch or missing | Part B6 — match `api://<app-id>` |

### C3. Confirm private DNS resolution from inside the VNet (optional, from the peered VM)
```powershell
ipconfig /flushdns
nslookup apim-agent-blueprint-dev-a5jiq4re.azure-api.net
```
✅ Expect: the APIM private IP `192.168.2.4` (NOT a public IP). This is the path the injected agent uses.

---

## Why this chapter is a new account (not an in-place change)

Foundry Agent Service **cannot add or change network injection after an agent has been created** on a
project. The original Chapter 01 account already had an agent, so this chapter provisions a **new**
Standard account/project (suffixed `-std`) on the same VNet. Migrate by rebuilding agents and tool
connections on the Standard project, validate here, then retire the old account.
