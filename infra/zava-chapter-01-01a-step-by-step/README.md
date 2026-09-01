# Zava Chapters 01 and 01a — Step-by-Step Deployment

This folder is a Zava-specific, brownfield deployment sequence. Each stage is intentionally separate so the Azure change set can be reviewed, deployed, and validated before proceeding.

## Interactive notebook

Open `ZAVA-CHAPTER-01-01A-DEPLOYMENT.dib` with the VS Code **Polyglot Notebooks** extension (`ms-dotnettools.dotnet-interactive-vscode`) for a clickable PowerShell notebook experience. Run cells from top to bottom. Azure-changing cells are blocked by explicit approval variables that default to `$false`.

The notebook displays the Bicep source, compiles it, validates it, runs what-if, and deploys each stage separately. `MANUAL-DEPLOYMENT-GUIDE.md` remains the complete written runbook.

## Supplied network and corrected address plan

Customer input:

- VNet: `azr-133-eastus`
- Address space: `10.75.139.128/25`
- Existing `dmzsubnet-1`: supplied as `10.75.128/29`
- Existing `hybridsubnet-1`: `10.75.139.136/29`

`10.75.128/29` is not valid CIDR notation and is outside `10.75.139.128/25`. This implementation assumes the intended DMZ range is `10.75.139.128/29`. Confirm this correction with Zava before production deployment.

| Range | Size | Purpose | Status |
|---|---:|---|---|
| `10.75.139.128/29` | 8 addresses, 3 Azure-usable | `dmzsubnet-1` | Existing |
| `10.75.139.136/29` | 8 addresses, 3 Azure-usable | `hybridsubnet-1` | Existing |
| `10.75.139.144/28` | 16 addresses, 11 Azure-usable | `snet-zava-privateendpoints` | Created in Step 01 |
| `10.75.139.160/27` | 32 addresses, 27 Azure-usable | `snet-zava-foundry-agent` | Created in Step 01 |
| `10.75.139.192/26` | 64 addresses | Unallocated reserve | Preserved |

Microsoft requires the delegated Agent subnet to be `/27` or larger and recommends `/24`. Because Zava supplied only a `/25` VNet with two occupied ranges, `/27` is the largest practical allocation that preserves private endpoint capacity and reserve space. It is supported but provides less scaling headroom than the recommended `/24`.

The `/28` private endpoint subnet has 11 usable addresses. Chapters 01 and 01a consume seven addresses, leaving four. This is adequate for this scope but not for broad platform growth.

## What every stage creates

| Step | File | Creates | Production ownership |
|---:|---|---|---|
| 00 | `00-simulate-customer-network.bicep` | VNet and two occupied customer subnets | Lab only; Zava provides these |
| 00B | `00b-simulate-customer-dns.bicep` | Seven private DNS zones | Lab only; Zava DNS provides these |
| 01 | `01-create-foundry-subnets.bicep` | Agent `/27` and private endpoint `/28` subnets | Jointly approved network change |
| 02 | `02-link-customer-private-dns.bicep` | VNet links to seven existing zones | Zava DNS/platform step |
| 03 | `03-chapter-01-foundation.bicep` | Basic Foundry, project, Storage, Key Vault, three PEs | Workload team |
| 04 | `04-chapter-01a-standard-core.bicep` | Standard Foundry, project, Storage, Cosmos, Search, four PEs, RBAC, connections | Workload team |
| 05 | `05-chapter-01a-capability-hosts.bicep` | Account and project capability hosts | One-time workload step |
| 06 | `deploy.ps1 -Step Model` | Approved model deployment on Standard account | Workload team |

## Why two new subnets are required

The existing `/29` subnets cannot be reused:

- They have only three usable addresses each.
- The Foundry Agent subnet must be dedicated, delegated to `Microsoft.App/environments`, and at least `/27`.
- Private endpoints cannot share the delegated Agent subnet.
- The Standard account requires its own exclusive Agent subnet.

## DNS boundaries

The workload templates do not create private DNS zones or VNet links. They reference customer-owned zones and create private endpoint DNS zone groups, which register service records.

Required zones:

- `privatelink.cognitiveservices.azure.com`
- `privatelink.openai.azure.com`
- `privatelink.services.ai.azure.com`
- `privatelink.blob.core.windows.net`
- `privatelink.vaultcore.azure.net`
- `privatelink.documents.azure.com`
- `privatelink.search.windows.net`

If Zava does not permit the workload identity to associate private endpoints with central zones, the private endpoint DNS-zone groups must be moved into Zava's DNS automation.

## Prerequisites

- Subscription: `ME-MngEnvMCAP152025-snair-1`
- Lab workload/network/DNS RG: `rg-jnj-agentic-blueprint`
- Region: `eastus`
- Azure CLI and Bicep available
- `Contributor` on the workload RG
- `Role Based Access Control Administrator` for managed-identity role assignments
- Permission to create subnets in the customer VNet
- Permission to create VNet links and PE zone-group associations against customer DNS zones
- Required resource providers already registered by Zava
- Model quota and Azure AI Search Standard capacity confirmed

The script verifies provider state but never registers providers.

## Deployment safety behavior

Every Bicep stage performs:

1. Local Bicep compilation.
2. ARM validation.
3. Azure what-if preview.
4. Deployment only when `-Execute` is supplied.

The script verifies the immutable tenant ID instead of checking the user's email suffix, so guest accounts are supported.

---

# Lab deployment sequence

Run from the repository root. Execute each step separately; do not use `-Step All -Execute` for the first deployment.

## Step 00 — Simulate the Zava VNet

Skip this in the real customer environment.

Preview:

```powershell
.\infra\zava-chapter-01-01a-step-by-step\deploy.ps1 -Step CustomerNetwork
```

Execute after confirming the preview creates only the VNet and two existing/customer subnets:

```powershell
.\infra\zava-chapter-01-01a-step-by-step\deploy.ps1 -Step CustomerNetwork -Execute
```

Validate:

```powershell
az network vnet show -g rg-jnj-agentic-blueprint -n azr-133-eastus `
  --query '{addressSpace:addressSpace.addressPrefixes,location:location}' -o json

az network vnet subnet list -g rg-jnj-agentic-blueprint --vnet-name azr-133-eastus `
  --query '[].{name:name,prefix:addressPrefix}' -o table
```

Stop if the ranges differ from the approved address plan.

## Step 00B — Simulate customer private DNS zones

Skip this in Zava; obtain the real central DNS resource group instead.

```powershell
.\infra\zava-chapter-01-01a-step-by-step\deploy.ps1 -Step CustomerDns
.\infra\zava-chapter-01-01a-step-by-step\deploy.ps1 -Step CustomerDns -Execute
```

Validate:

```powershell
az network private-dns zone list -g rg-jnj-agentic-blueprint `
  --query '[].name' -o table
```

## Step 01 — Create the two Foundry subnets

This is the only stage that modifies Zava's VNet. The what-if must show exactly two subnet additions and no changes to `dmzsubnet-1` or `hybridsubnet-1`.

```powershell
.\infra\zava-chapter-01-01a-step-by-step\deploy.ps1 -Step Subnets
.\infra\zava-chapter-01-01a-step-by-step\deploy.ps1 -Step Subnets -Execute
```

Validate:

```powershell
az network vnet subnet list -g rg-jnj-agentic-blueprint --vnet-name azr-133-eastus `
  --query '[].{name:name,prefix:addressPrefix,delegation:delegations[0].serviceName,pePolicies:privateEndpointNetworkPolicies}' -o table
```

Expected:

- `snet-zava-foundry-agent` → `10.75.139.160/27`, delegated to `Microsoft.App/environments`
- `snet-zava-privateendpoints` → `10.75.139.144/28`, PE policies disabled
- Existing subnet ranges unchanged

## Step 02 — Link customer DNS zones

This stage is normally performed or approved by Zava's DNS team.

```powershell
.\infra\zava-chapter-01-01a-step-by-step\deploy.ps1 -Step DnsLinks
.\infra\zava-chapter-01-01a-step-by-step\deploy.ps1 -Step DnsLinks -Execute
```

Validate all seven links:

```powershell
$zones = @(
  'privatelink.cognitiveservices.azure.com',
  'privatelink.openai.azure.com',
  'privatelink.services.ai.azure.com',
  'privatelink.blob.core.windows.net',
  'privatelink.vaultcore.azure.net',
  'privatelink.documents.azure.com',
  'privatelink.search.windows.net'
)
foreach ($zone in $zones) {
  az network private-dns link vnet list -g rg-jnj-agentic-blueprint -z $zone `
    --query '[].{zone:`"'$zone'`",name:name,state:virtualNetworkLinkState,vnet:virtualNetwork.id}' -o table
}
```

## Step 03 — Deploy Chapter 01 foundation

Creates the original private Foundry foundation and three private endpoints. No model is deployed yet.

```powershell
.\infra\zava-chapter-01-01a-step-by-step\deploy.ps1 -Step Chapter01
.\infra\zava-chapter-01-01a-step-by-step\deploy.ps1 -Step Chapter01 -Execute
```

Review the what-if carefully. It must not create or modify VNets, subnets, DNS zones, DNS VNet links, routes, NSGs, or firewalls.

Validate:

```powershell
az deployment group show -g rg-jnj-agentic-blueprint -n zava-03-chapter-01-dev `
  --query properties.outputs -o json

az network private-endpoint list -g rg-jnj-agentic-blueprint `
  --query '[].{name:name,state:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status,subnet:subnet.id}' -o table
```

Expected Chapter 01 resources:

- Private Basic Foundry account and project
- Private Storage account with shared keys disabled
- Private Key Vault using RBAC and purge protection
- Foundry, Blob, and Key Vault private endpoints
- Foundry User assignment for the selected operator

## Step 04 — Deploy Chapter 01a Standard core

This is the primary production environment. It configures network injection during account creation and creates customer-owned agent state.

```powershell
.\infra\zava-chapter-01-01a-step-by-step\deploy.ps1 -Step Chapter01aCore
.\infra\zava-chapter-01-01a-step-by-step\deploy.ps1 -Step Chapter01aCore -Execute
```

Expected resources:

- Network-injected Standard Foundry account
- Standard Foundry project and managed identity
- Private agent file Storage
- Private Cosmos DB thread/message store
- Private Azure AI Search vector store
- Four private endpoints
- Five project-identity access assignments
- Three AAD project connections

Validate outputs and security posture:

```powershell
$deployment = 'zava-04-chapter-01a-core-dev'
$outputs = az deployment group show -g rg-jnj-agentic-blueprint -n $deployment `
  --query properties.outputs -o json | ConvertFrom-Json

$account = $outputs.foundryAccountName.value
$cosmos  = $outputs.cosmosAccountName.value
$search  = $outputs.searchServiceName.value
$storage = $outputs.storageAccountName.value

az cognitiveservices account show -g rg-jnj-agentic-blueprint -n $account `
  --query '{name:name,public:properties.publicNetworkAccess,localAuth:properties.disableLocalAuth,injection:properties.networkInjections}' -o json
az cosmosdb show -g rg-jnj-agentic-blueprint -n $cosmos `
  --query '{public:publicNetworkAccess,localAuth:disableLocalAuth}' -o json
az search service show -g rg-jnj-agentic-blueprint -n $search `
  --query '{public:publicNetworkAccess,localAuth:disableLocalAuth}' -o json
az storage account show -g rg-jnj-agentic-blueprint -n $storage `
  --query '{public:publicNetworkAccess,sharedKey:allowSharedKeyAccess}' -o json
```

Expected: public access disabled and local/shared-key authentication disabled.

## Required DNS checkpoint before capability hosts

From a host connected to `azr-133-eastus` or a peered network using Zava DNS:

```powershell
nslookup "$account.cognitiveservices.azure.com"
nslookup "$account.openai.azure.com"
nslookup "$storage.blob.core.windows.net"
nslookup "$cosmos.documents.azure.com"
nslookup "$search.search.windows.net"
```

All results must return private IP addresses from `10.75.139.144/28`. Do not run Step 05 until this passes.

Also confirm all four Step 04 private endpoints are `Approved` and the project identity has its Storage, Cosmos, and Search roles.

## Step 05 — Create capability hosts once

Capability hosts cause Foundry to provision and use agent state in Storage, Cosmos DB, and Search. They are separated because creation is not reliably idempotent.

Preview and execute once:

```powershell
.\infra\zava-chapter-01-01a-step-by-step\deploy.ps1 -Step CapabilityHosts
.\infra\zava-chapter-01-01a-step-by-step\deploy.ps1 -Step CapabilityHosts -Execute
```

The script refuses to continue if either host already exists.

Validate:

```powershell
$accountId = az cognitiveservices account show -g rg-jnj-agentic-blueprint -n $account --query id -o tsv
$project = 'zava-dev-project-std'

az rest --method GET --url "https://management.azure.com$accountId/capabilityHosts?api-version=2025-06-01" `
  --query 'value[].{name:name,state:properties.provisioningState}' -o table
az rest --method GET --url "https://management.azure.com$accountId/projects/$project/capabilityHosts?api-version=2025-06-01" `
  --query 'value[].{name:name,state:properties.provisioningState,storage:properties.storageConnections,threads:properties.threadStorageConnections,vectors:properties.vectorStoreConnections}' -o json
```

Both hosts must reach `Succeeded`.

### Partial-failure rule

Do not rerun Step 05. Query both host collections first. If a host is missing, use `recover-capability-hosts.ps1`; it creates only a missing account or project host and refuses to overwrite an existing failed host. See the recovery section in `MANUAL-DEPLOYMENT-GUIDE.md` for the exact command.

## Step 06 — Deploy the approved model

Only proceed after both capability hosts succeed and quota is approved.

Preview the intended model values:

```powershell
.\infra\zava-chapter-01-01a-step-by-step\deploy.ps1 -Step Model
```

Deploy:

```powershell
.\infra\zava-chapter-01-01a-step-by-step\deploy.ps1 `
  -Step Model `
  -ModelDeploymentName 'gpt-4o' `
  -ModelName 'gpt-4o' `
  -ModelVersion '2024-11-20' `
  -ModelCapacity 30 `
  -Execute
```

Replace these defaults with Zava-approved model, version, SKU capacity, and quota.

Validate:

```powershell
az cognitiveservices account deployment list -g rg-jnj-agentic-blueprint -n $account `
  --query '[].{name:name,model:properties.model.name,version:properties.model.version,state:properties.provisioningState,capacity:sku.capacity}' -o table
```

---

# Production parameter overrides

If the real VNet, DNS zones, and workload resources are in separate resource groups:

```powershell
.\infra\zava-chapter-01-01a-step-by-step\deploy.ps1 `
  -Step Chapter01aCore `
  -Subscription '<Zava-subscription-id-or-name>' `
  -TenantId '<Zava-tenant-id>' `
  -WorkloadResourceGroupName '<Zava-workload-rg>' `
  -NetworkResourceGroupName '<Zava-network-rg>' `
  -PrivateDnsResourceGroupName '<Zava-private-dns-rg>' `
  -Location 'eastus' `
  -SearchLocation 'eastus' `
  -VnetName 'azr-133-eastus' `
  -AgentSubnetName 'snet-zava-foundry-agent' `
  -PrivateEndpointSubnetName 'snet-zava-privateendpoints' `
  -WorkloadName 'zava' `
  -Environment 'dev'
```

Run once without `-Execute`, obtain customer approval of the what-if, then rerun with `-Execute`.

## Final acceptance criteria

- Existing DMZ and hybrid subnets are unchanged.
- Agent subnet is `/27`, exclusive, and delegated to `Microsoft.App/environments`.
- Private endpoint subnet is `/28` and contains only approved private endpoints.
- No workload stage creates customer DNS zones or links.
- All seven private endpoints are approved.
- All service FQDNs resolve to private endpoint addresses from the customer network.
- Public access is disabled for Foundry, Storage, Key Vault, Cosmos DB, and Search.
- Shared/local keys are disabled where supported.
- Standard account `networkInjections` references `snet-zava-foundry-agent`.
- Both capability hosts report `Succeeded`.
- The approved model reports `Succeeded`.
- A temporary Standard-project agent can create a thread and perform a model response through the private path.
