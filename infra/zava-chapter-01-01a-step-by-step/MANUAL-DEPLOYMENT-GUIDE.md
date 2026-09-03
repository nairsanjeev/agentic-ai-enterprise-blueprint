# Zava Manual Deployment Guide — Chapters 01 and 01a

This guide deploys Chapters 01 and 01a manually, one stage at a time, into Zava's existing network. After every stage, validate the resources before proceeding.

No orchestration script is required. All commands are intended to be run manually from the repository root in PowerShell.

---

## Before you begin: open PowerShell in VS Code

Use one PowerShell terminal for the entire deployment. The values entered in Section 2 are stored only in that terminal and will be lost if it is closed.

### A. Open the repository

1. Start Visual Studio Code.
2. Select **File > Open Folder**.
3. Select the `Governed Agentic Framework` folder.
4. If VS Code asks whether you trust the folder, review the folder location and select **Yes, I trust the authors** only if it is the expected repository.

### B. Open a PowerShell terminal

1. Select **Terminal > New Terminal** from the VS Code menu.
2. A terminal panel opens at the bottom of VS Code.
3. Check that the prompt starts with `PS`. If it does not, select the arrow next to the **+** in the terminal panel, select **PowerShell**, and close the other terminal.
4. Check that the prompt ends with the repository folder, similar to:

   ```text
   PS C:\Governed Agentic Framework>
   ```

5. If the terminal is in a different folder, run:

   ```powershell
   Set-Location 'C:\Governed Agentic Framework'
   ```

   If the repository was saved somewhere else, use that folder path instead.

### C. Check the required command-line tools

Copy the following block, paste it into the terminal, and press **Enter**:

```powershell
$PSVersionTable.PSVersion
az version
```

- PowerShell should print a version. PowerShell 7 or later is recommended.
- Azure CLI should print version information. If `az` is not recognized, install Azure CLI, restart VS Code, and repeat this check.
- Do not continue until both commands work.

### D. How to run the commands in this guide

1. Copy one complete PowerShell block at a time, including its first and last lines.
2. Click inside the PowerShell terminal, paste the block, and press **Enter**.
3. A backtick (`` ` ``) at the end of a line means the command continues on the next line. Do not add spaces after a backtick.
4. Wait until the `PS ...>` prompt returns before running the next block.
5. Read the output and complete each validation step before moving to the next numbered section.
6. Keep the same terminal open throughout the deployment. If it is closed or VS Code is restarted, return to Section 2 and set the PowerShell values again.

> **Important:** Do not use the editor's **Run Code** button for these commands. Paste them into the PowerShell terminal. Preview or validation commands are safe checks; run resource-creating commands only after reviewing their values and output.

### E. If PowerShell reports that script execution is disabled

This guide mostly runs commands directly. If a trusted repository script is blocked by the local execution policy, run the following once in the same terminal and then retry it:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
```

This changes the policy only for the current PowerShell process. Closing the terminal removes the change. Do not change the machine-wide execution policy.

---

## 1. Confirm the network information first

Zava supplied:

- VNet: `azr-133-eastus`
- Region: `eastus`
- VNet address space: `10.75.139.128/25`
- Existing subnet: `dmzsubnet-1`
- Existing subnet: `hybridsubnet-1` — `10.75.139.136/29`

The supplied DMZ value `10.75.128/29` is incomplete and outside `10.75.139.128/25`. This guide assumes the intended value is:

- `dmzsubnet-1` — `10.75.139.128/29`

**Obtain written confirmation from Zava before creating any subnet.**

### Proposed address allocation

| Subnet/range | CIDR | Azure-usable addresses | Purpose |
|---|---|---:|---|
| `dmzsubnet-1` | `10.75.139.128/29` | 3 | Existing—do not modify |
| `hybridsubnet-1` | `10.75.139.136/29` | 3 | Existing—do not modify |
| `snet-zava-privateendpoints` | `10.75.139.144/28` | 11 | Seven Chapter 01/01a private endpoints |
| `snet-zava-foundry-agent` | `10.75.139.160/27` | 27 | Dedicated Standard Foundry agent injection |
| Unallocated reserve | `10.75.139.192/26` | 59 | Reserved for future use |

### Important capacity warning

Microsoft requires the Foundry agent subnet to be `/27` or larger and recommends `/24`. Zava's entire VNet is only `/25`, so this design uses the minimum supported `/27`.

The agent subnet:

- Must be delegated to `Microsoft.App/environments`.
- Must be dedicated to one Standard Foundry account.
- Cannot contain private endpoints.
- Cannot be shared with another Foundry account's agent runtime.

The `/28` private endpoint subnet provides 11 usable addresses. Chapters 01 and 01a use seven, leaving four available addresses.

> **Production scale decision:** `/27` is the minimum supported size, not Microsoft's recommended size. Before continuing, Zava must accept the reduced scaling and upgrade headroom or provide a larger VNet/address range that permits a dedicated `/24` agent subnet. Do not assume the remaining 27 usable addresses map directly to 27 concurrent agents; the service consumes addresses for managed infrastructure and scaling.

---

## 2. Gather Zava deployment values

Before running commands, obtain:

```text
Zava tenant ID:
Zava subscription ID or name:
Workload resource group:
Network resource group:
Private DNS resource group:
VNet name: azr-133-eastus
VNet region: eastus
Operator/Foundry user object ID:
Approved model name:
Approved model version:
Approved model capacity:
Approved Azure AI Search region:
```

Set the values in PowerShell:

```powershell
$tenantId       = '<Zava-tenant-id>'
$subscription   = '<Zava-subscription-id-or-name>'
$workloadRg     = '<Zava-workload-resource-group>'
$networkRg      = '<Zava-network-resource-group>'
$dnsRg          = '<Zava-private-dns-resource-group>'
$location       = 'eastus'
$searchLocation = 'eastus'
$vnet            = 'azr-133-eastus'
$agentSubnet     = 'snet-zava-foundry-agent'
$agentSubnetPrefix = '10.75.139.160/27'
$peSubnet        = 'snet-zava-privateendpoints'
$peSubnetPrefix  = '10.75.139.144/28'
$workload        = 'zava'
$environment     = 'dev'

# true: this deployment creates private endpoint DNS-zone groups in Zava's zones.
# false: Zava DNS automation creates the zone groups/records after each PE is created.
$createPrivateEndpointDnsZoneGroups = $true

az login --tenant $tenantId --use-device-code
az account set --subscription $subscription
az account show `
  --query '{subscription:name,subscriptionId:id,tenantId:tenantId,user:user.name}' `
  --output table
```

Stop if the displayed subscription or tenant is incorrect.

Resolve the signed-in user's object ID, or replace it with an approved group/user object ID:

```powershell
$foundryUserObjectId = az ad signed-in-user show --query id --output tsv
Write-Host "Foundry user object ID: $foundryUserObjectId"
```

---

## 3. Confirm required permissions

The deploying identity needs:

### Workload resource group

- `Contributor`
- `Role Based Access Control Administrator` or `User Access Administrator`

The role-assignment permission is required because Chapter 01a grants the project managed identity access to Storage, Cosmos DB, and Azure AI Search.

### Network scope

- Permission to read the VNet
- Permission to create the two subnets
- `Microsoft.Network/virtualNetworks/subnets/join/action`

### Private DNS scope

If this deployment creates VNet links and private endpoint DNS-zone groups:

- Permission to read the seven private DNS zones
- Permission to create VNet links
- Permission to associate private endpoints with the zones

If Zava's DNS team performs these tasks, do not run the DNS-link step. Provide the VNet and private endpoint details to that team.

---

## 4. Confirm resource providers

Zava's subscription team must register these providers:

```powershell
$providers = @(
  'Microsoft.App',
  'Microsoft.CognitiveServices',
  'Microsoft.ContainerService',
  'Microsoft.DocumentDB',
  'Microsoft.KeyVault',
  'Microsoft.Network',
  'Microsoft.Search',
  'Microsoft.Storage'
)

foreach ($provider in $providers) {
  az provider show `
    --namespace $provider `
    --query '{provider:namespace,state:registrationState}' `
    --output table
}
```

Every provider must report `Registered`. Ask Zava's subscription administrator to register missing providers.

---

## 5. Validate the existing VNet and occupied subnets

```powershell
az network vnet show `
  --resource-group $networkRg `
  --name $vnet `
  --query '{name:name,location:location,addressSpace:addressSpace.addressPrefixes,state:provisioningState}' `
  --output json

az network vnet subnet list `
  --resource-group $networkRg `
  --vnet-name $vnet `
  --query '[].{name:name,prefix:addressPrefix,state:provisioningState}' `
  --output table
```

Confirm:

- The VNet is in `eastus`.
- The VNet address space is `10.75.139.128/25`.
- `dmzsubnet-1` is confirmed as `10.75.139.128/29`.
- `hybridsubnet-1` is `10.75.139.136/29`.
- Neither proposed new range is already allocated.

Do not proceed if any range overlaps.

---

# Chapter 01 networking preparation

## 6. Create the private endpoint subnet and agent subnet

Template:

- `01-create-foundry-subnets.bicep`

This stage creates only:

1. `snet-zava-privateendpoints` — `10.75.139.144/28`
2. `snet-zava-foundry-agent` — `10.75.139.160/27`

It does not modify the existing DMZ or hybrid subnets.

### 6.1 Compile

```powershell
az bicep build `
  --file .\infra\zava-chapter-01-01a-step-by-step\01-create-foundry-subnets.bicep
```

### 6.2 Validate

```powershell
az deployment group validate `
  --resource-group $networkRg `
  --name 'zava-01-foundry-subnets-validate' `
  --template-file .\infra\zava-chapter-01-01a-step-by-step\01-create-foundry-subnets.bicep `
  --parameters `
    vnetName=$vnet `
    agentSubnetName=$agentSubnet `
    agentSubnetPrefix=$agentSubnetPrefix `
    privateEndpointSubnetName=$peSubnet `
    privateEndpointSubnetPrefix=$peSubnetPrefix `
  --output none
```

### 6.3 Preview

```powershell
az deployment group what-if `
  --resource-group $networkRg `
  --name 'zava-01-foundry-subnets' `
  --template-file .\infra\zava-chapter-01-01a-step-by-step\01-create-foundry-subnets.bicep `
  --parameters `
    vnetName=$vnet `
    agentSubnetName=$agentSubnet `
    agentSubnetPrefix=$agentSubnetPrefix `
    privateEndpointSubnetName=$peSubnet `
    privateEndpointSubnetPrefix=$peSubnetPrefix `
  --result-format ResourceIdOnly
```

Expected: exactly two subnet creations. Stop if existing subnets are modified or deleted.

### 6.4 Deploy

```powershell
az deployment group create `
  --resource-group $networkRg `
  --name 'zava-01-foundry-subnets' `
  --template-file .\infra\zava-chapter-01-01a-step-by-step\01-create-foundry-subnets.bicep `
  --parameters `
    vnetName=$vnet `
    agentSubnetName=$agentSubnet `
    agentSubnetPrefix=$agentSubnetPrefix `
    privateEndpointSubnetName=$peSubnet `
    privateEndpointSubnetPrefix=$peSubnetPrefix `
  --output none
```

### 6.5 Validate each subnet

```powershell
az network vnet subnet show `
  --resource-group $networkRg `
  --vnet-name $vnet `
  --name $agentSubnet `
  --query '{name:name,prefix:addressPrefix,delegation:delegations[].serviceName,state:provisioningState}' `
  --output json

az network vnet subnet show `
  --resource-group $networkRg `
  --vnet-name $vnet `
  --name $peSubnet `
  --query '{name:name,prefix:addressPrefix,privateEndpointPolicies:privateEndpointNetworkPolicies,state:provisioningState}' `
  --output json
```

Expected:

- Agent subnet prefix: `10.75.139.160/27`
- Delegation: `Microsoft.App/environments`
- Private endpoint subnet prefix: `10.75.139.144/28`
- Private endpoint network policies: `Disabled`

Re-list all subnets and ensure the two original subnets remain unchanged.

---

## 7. Confirm the seven customer-owned private DNS zones

### What customer-owned means

These are Azure Private DNS zone resources owned and governed by Zava's central networking/DNS team. They are not application resources, and the Chapter 01/01a templates do not create them. The workload templates only reference them when associating private endpoints with the correct namespaces.

In a typical hub-and-spoke design, the zones live in a connectivity subscription or central DNS resource group. Azure Private DNS zones are global resources; they do not physically live inside a hub VNet. The hub commonly contains Azure Private DNS Resolver or DNS forwarders, while the zones are linked to the hub, directly to spokes, or both according to the enterprise DNS design.

| Zone | Workload use |
|---|---|
| `privatelink.cognitiveservices.azure.com` | Foundry account private endpoint |
| `privatelink.openai.azure.com` | Azure OpenAI-compatible Foundry endpoint |
| `privatelink.services.ai.azure.com` | Foundry project/service endpoint |
| `privatelink.blob.core.windows.net` | Chapter 01 and 01a Blob Storage endpoints |
| `privatelink.vaultcore.azure.net` | Chapter 01 Key Vault endpoint |
| `privatelink.documents.azure.com` | Chapter 01a Cosmos DB SQL endpoint |
| `privatelink.search.windows.net` | Chapter 01a Azure AI Search endpoint |

### Choose the correct hub-and-spoke resolution pattern

**Pattern A — direct spoke links:** Link each central zone directly to `azr-133-eastus`. Use this when the spoke uses Azure-provided DNS or Zava's standard explicitly requires direct links. Step 8 implements this pattern.

**Pattern B — central hub resolver:** The spoke sends DNS to Zava DNS servers or Azure Private DNS Resolver in the hub. The zones may be linked only to the resolver/hub VNet, and Step 8 must be skipped. VNet peering does not make private DNS links transitive; resolution works because the configured DNS resolver queries the linked zones.

Before selecting a pattern, ask Zava:

1. Does `azr-133-eastus` use Azure-provided DNS or custom DNS servers?
2. Is Azure Private DNS Resolver deployed in the hub?
3. Are central private zones linked directly to every spoke?
4. Who creates private endpoint DNS-zone groups and records?
5. Can the workload identity reference/write the central zones, or must the DNS team perform the association?

Do not create duplicate zones in the workload resource group. If Zava owns private endpoint record registration, the DNS-zone-group resources in Steps 9 and 10 must be deployed by Zava's DNS automation instead of the workload identity.

Set `$createPrivateEndpointDnsZoneGroups = $true` only when the deployment identity is authorized to associate private endpoints with the central zones. Otherwise set it to `$false`, deploy the endpoints, and stop for Zava's DNS team to register the records before proceeding to the DNS checkpoint and capability hosts.

Required zones:

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
  az network private-dns zone show `
    --resource-group $dnsRg `
    --name $zone `
    --query '{name:name,id:id}' `
    --output table
}
```

Every lookup must succeed. These zones are customer resources and are not created by the Chapter 01/01a workload templates.

---

## 8. Link the private DNS zones to the VNet

Run this stage only for direct spoke links (Pattern A). Skip it when Zava uses the central hub-resolver pattern (Pattern B) or when Zava's DNS team manages links independently.

Before skipping it, have the DNS team confirm that a client using the spoke's configured DNS servers can resolve all seven private namespaces. Merely linking each zone to the hub while the spoke uses Azure-provided DNS is not sufficient.

Template:

- `02-link-customer-private-dns.bicep`

The deployment scope must be the private DNS resource group.

### 8.1 Compile

```powershell
az bicep build `
  --file .\infra\zava-chapter-01-01a-step-by-step\02-link-customer-private-dns.bicep
```

### 8.2 Validate and preview

```powershell
az deployment group validate `
  --resource-group $dnsRg `
  --name 'zava-02-private-dns-links-validate' `
  --template-file .\infra\zava-chapter-01-01a-step-by-step\02-link-customer-private-dns.bicep `
  --parameters `
    networkResourceGroupName=$networkRg `
    vnetName=$vnet `
  --output none

az deployment group what-if `
  --resource-group $dnsRg `
  --name 'zava-02-private-dns-links' `
  --template-file .\infra\zava-chapter-01-01a-step-by-step\02-link-customer-private-dns.bicep `
  --parameters `
    networkResourceGroupName=$networkRg `
    vnetName=$vnet `
  --result-format ResourceIdOnly
```

Expected: seven VNet links and no DNS-zone modifications or deletions.

### 8.3 Deploy

```powershell
az deployment group create `
  --resource-group $dnsRg `
  --name 'zava-02-private-dns-links' `
  --template-file .\infra\zava-chapter-01-01a-step-by-step\02-link-customer-private-dns.bicep `
  --parameters `
    networkResourceGroupName=$networkRg `
    vnetName=$vnet `
  --output none
```

### 8.4 Validate every link

```powershell
foreach ($zone in $zones) {
  Write-Host "--- $zone ---"
  az network private-dns link vnet list `
    --resource-group $dnsRg `
    --zone-name $zone `
    --query "[?contains(virtualNetwork.id, '/virtualNetworks/$vnet')].{name:name,state:virtualNetworkLinkState,vnet:virtualNetwork.id}" `
    --output table
}
```

Every zone must show a link to `azr-133-eastus` in `Completed` state.

For the hub-resolver pattern, direct links may intentionally be absent. Instead, validate from a host in the spoke that the DNS server shown by `ipconfig /all` is the approved Zava resolver and that private endpoint names resolve privately after Steps 9 and 10.

---

# Chapter 01 deployment

## 9. Deploy the Chapter 01 private foundation

Template:

- `03-chapter-01-foundation.bicep`

This stage creates:

1. Chapter 01 Foundry account
2. Chapter 01 Foundry project
3. Private Storage account
4. Private Key Vault
5. Foundry private endpoint and DNS-zone group
6. Blob private endpoint and DNS-zone group
7. Key Vault private endpoint and DNS-zone group
8. Optional Foundry User assignment

It does not deploy a model and does not modify customer network or DNS links.

### 9.1 Compile

```powershell
az bicep build `
  --file .\infra\zava-chapter-01-01a-step-by-step\03-chapter-01-foundation.bicep
```

### 9.2 Validate

```powershell
az deployment group validate `
  --resource-group $workloadRg `
  --name "zava-03-chapter-01-$environment-validate" `
  --template-file .\infra\zava-chapter-01-01a-step-by-step\03-chapter-01-foundation.bicep `
  --parameters `
    location=$location `
    workloadName=$workload `
    environment=$environment `
    networkResourceGroupName=$networkRg `
    vnetName=$vnet `
    privateEndpointSubnetName=$peSubnet `
    privateDnsResourceGroupName=$dnsRg `
    createPrivateEndpointDnsZoneGroups=$createPrivateEndpointDnsZoneGroups `
    foundryUserPrincipalId=$foundryUserObjectId `
  --output none
```

### 9.3 Preview

```powershell
az deployment group what-if `
  --resource-group $workloadRg `
  --name "zava-03-chapter-01-$environment" `
  --template-file .\infra\zava-chapter-01-01a-step-by-step\03-chapter-01-foundation.bicep `
  --parameters `
    location=$location `
    workloadName=$workload `
    environment=$environment `
    networkResourceGroupName=$networkRg `
    vnetName=$vnet `
    privateEndpointSubnetName=$peSubnet `
    privateDnsResourceGroupName=$dnsRg `
    createPrivateEndpointDnsZoneGroups=$createPrivateEndpointDnsZoneGroups `
    foundryUserPrincipalId=$foundryUserObjectId `
  --result-format ResourceIdOnly
```

Stop if the preview creates or changes:

- VNet or subnets
- DNS zones or VNet links
- Route tables
- NSGs
- Firewall resources

### 9.4 Deploy

```powershell
az deployment group create `
  --resource-group $workloadRg `
  --name "zava-03-chapter-01-$environment" `
  --template-file .\infra\zava-chapter-01-01a-step-by-step\03-chapter-01-foundation.bicep `
  --parameters `
    location=$location `
    workloadName=$workload `
    environment=$environment `
    networkResourceGroupName=$networkRg `
    vnetName=$vnet `
    privateEndpointSubnetName=$peSubnet `
    privateDnsResourceGroupName=$dnsRg `
    createPrivateEndpointDnsZoneGroups=$createPrivateEndpointDnsZoneGroups `
    foundryUserPrincipalId=$foundryUserObjectId `
  --output none
```

### 9.5 Capture outputs

```powershell
$chapter01Deployment = "zava-03-chapter-01-$environment"
$chapter01Outputs = az deployment group show `
  --resource-group $workloadRg `
  --name $chapter01Deployment `
  --query properties.outputs `
  --output json | ConvertFrom-Json

$basicFoundry = $chapter01Outputs.foundryAccountName.value
$basicProject = $chapter01Outputs.foundryProjectName.value
$basicStorage = $chapter01Outputs.storageAccountName.value
$basicVault   = $chapter01Outputs.keyVaultName.value
```

### 9.6 Validate the Chapter 01 Foundry account

```powershell
az cognitiveservices account show `
  --resource-group $workloadRg `
  --name $basicFoundry `
  --query '{name:name,state:properties.provisioningState,public:properties.publicNetworkAccess,localAuthDisabled:properties.disableLocalAuth}' `
  --output table
```

Expected:

- State: `Succeeded`
- Public access: `Disabled`
- Local authentication disabled: `True`

### 9.7 Validate Storage

```powershell
az storage account show `
  --resource-group $workloadRg `
  --name $basicStorage `
  --query '{name:name,state:provisioningState,public:publicNetworkAccess,sharedKey:allowSharedKeyAccess,blobPublic:allowBlobPublicAccess,tls:minimumTlsVersion}' `
  --output table
```

Expected: public access disabled, shared keys disabled, Blob public access disabled, and TLS 1.2.

### 9.8 Validate Key Vault

```powershell
az keyvault show `
  --resource-group $workloadRg `
  --name $basicVault `
  --query '{name:name,public:properties.publicNetworkAccess,rbac:properties.enableRbacAuthorization,purgeProtection:properties.enablePurgeProtection}' `
  --output table
```

Expected: public access disabled, RBAC enabled, and purge protection enabled.

### 9.9 Validate Chapter 01 private endpoints

```powershell
az network private-endpoint list `
  --resource-group $workloadRg `
  --query "[?contains(name, '$basicFoundry') || contains(name, '$basicStorage') || contains(name, '$basicVault')].{name:name,state:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status,subnet:subnet.id}" `
  --output table
```

Expected: three private endpoints, all `Approved`, all using `snet-zava-privateendpoints`.

---

# Chapter 01a deployment

## 10. Deploy the Chapter 01a Standard core

Template:

- `04-chapter-01a-standard-core.bicep`

This stage creates:

1. Network-injected Standard Foundry account
2. Standard Foundry project and managed identity
3. Private agent Storage account
4. Private Cosmos DB account
5. Private Azure AI Search service
6. Four private endpoints and DNS-zone groups
7. Storage Blob Data Owner assignment
8. Cosmos DB Operator assignment
9. Cosmos DB SQL Data Contributor assignment
10. Search Index Data Contributor assignment
11. Search Service Contributor assignment
12. Foundry User assignment
13. Storage, Cosmos DB, and Search AAD project connections

Capability hosts and models are deliberately deployed later.

### 10.1 Compile

```powershell
az bicep build `
  --file .\infra\zava-chapter-01-01a-step-by-step\04-chapter-01a-standard-core.bicep
```

### 10.2 Validate

```powershell
az deployment group validate `
  --resource-group $workloadRg `
  --name "zava-04-chapter-01a-core-$environment-validate" `
  --template-file .\infra\zava-chapter-01-01a-step-by-step\04-chapter-01a-standard-core.bicep `
  --parameters `
    location=$location `
    searchLocation=$searchLocation `
    workloadName=$workload `
    environment=$environment `
    networkResourceGroupName=$networkRg `
    vnetName=$vnet `
    agentSubnetName=$agentSubnet `
    privateEndpointSubnetName=$peSubnet `
    privateDnsResourceGroupName=$dnsRg `
    createPrivateEndpointDnsZoneGroups=$createPrivateEndpointDnsZoneGroups `
    foundryUserPrincipalId=$foundryUserObjectId `
  --output none
```

### 10.3 Preview

```powershell
az deployment group what-if `
  --resource-group $workloadRg `
  --name "zava-04-chapter-01a-core-$environment" `
  --template-file .\infra\zava-chapter-01-01a-step-by-step\04-chapter-01a-standard-core.bicep `
  --parameters `
    location=$location `
    searchLocation=$searchLocation `
    workloadName=$workload `
    environment=$environment `
    networkResourceGroupName=$networkRg `
    vnetName=$vnet `
    agentSubnetName=$agentSubnet `
    privateEndpointSubnetName=$peSubnet `
    privateDnsResourceGroupName=$dnsRg `
    createPrivateEndpointDnsZoneGroups=$createPrivateEndpointDnsZoneGroups `
    foundryUserPrincipalId=$foundryUserObjectId `
  --result-format ResourceIdOnly
```

Confirm that no customer VNet, subnet, route, NSG, firewall, DNS zone, or DNS VNet link is modified.

### 10.4 Deploy

```powershell
az deployment group create `
  --resource-group $workloadRg `
  --name "zava-04-chapter-01a-core-$environment" `
  --template-file .\infra\zava-chapter-01-01a-step-by-step\04-chapter-01a-standard-core.bicep `
  --parameters `
    location=$location `
    searchLocation=$searchLocation `
    workloadName=$workload `
    environment=$environment `
    networkResourceGroupName=$networkRg `
    vnetName=$vnet `
    agentSubnetName=$agentSubnet `
    privateEndpointSubnetName=$peSubnet `
    privateDnsResourceGroupName=$dnsRg `
    createPrivateEndpointDnsZoneGroups=$createPrivateEndpointDnsZoneGroups `
    foundryUserPrincipalId=$foundryUserObjectId `
  --output none
```

### 10.5 Capture outputs

```powershell
$coreDeployment = "zava-04-chapter-01a-core-$environment"
$coreOutputs = az deployment group show `
  --resource-group $workloadRg `
  --name $coreDeployment `
  --query properties.outputs `
  --output json | ConvertFrom-Json

$stdFoundry = $coreOutputs.foundryAccountName.value
$stdProject = $coreOutputs.foundryProjectName.value
$stdStorage = $coreOutputs.storageAccountName.value
$cosmos     = $coreOutputs.cosmosAccountName.value
$search     = $coreOutputs.searchServiceName.value
$projectMi  = $coreOutputs.projectPrincipalId.value
$stdId      = $coreOutputs.foundryAccountId.value

if (-not $stdFoundry -or -not $stdProject -or -not $stdStorage -or -not $cosmos -or -not $search -or -not $projectMi -or -not $stdId) {
  throw "Chapter 01a outputs are incomplete. Inspect deployment $coreDeployment before continuing."
}
```

### 10.6 Validate network injection

```powershell
az rest `
  --method GET `
  --url "https://management.azure.com${stdId}?api-version=2025-06-01" `
  --query properties.networkInjections `
  --output json
```

Expected:

- `scenario`: `agent`
- `subnetArmId`: ends with `/subnets/snet-zava-foundry-agent`
- `useMicrosoftManagedNetwork`: `false`

Do not create agents if this property is absent or incorrect.

### 10.7 Validate Standard Foundry security

```powershell
az cognitiveservices account show `
  --resource-group $workloadRg `
  --name $stdFoundry `
  --query '{name:name,state:properties.provisioningState,public:properties.publicNetworkAccess,localAuthDisabled:properties.disableLocalAuth}' `
  --output table
```

Expected: `Succeeded`, public access disabled, local authentication disabled.

### 10.8 Validate agent Storage

```powershell
az storage account show `
  --resource-group $workloadRg `
  --name $stdStorage `
  --query '{name:name,state:provisioningState,public:publicNetworkAccess,sharedKey:allowSharedKeyAccess}' `
  --output table
```

### 10.9 Validate Cosmos DB

```powershell
az cosmosdb show `
  --resource-group $workloadRg `
  --name $cosmos `
  --query '{name:name,state:provisioningState,public:publicNetworkAccess,localAuthDisabled:disableLocalAuth}' `
  --output table
```

### 10.10 Validate Azure AI Search

```powershell
az search service show `
  --resource-group $workloadRg `
  --name $search `
  --query '{name:name,state:status,public:publicNetworkAccess,localAuthDisabled:disableLocalAuth,sku:sku.name}' `
  --output table
```

Expected SKU: `standard`; public and local authentication disabled.

### 10.11 Validate all seven private endpoints

```powershell
az network private-endpoint list `
  --resource-group $workloadRg `
  --query '[].{name:name,state:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status,subnet:subnet.id}' `
  --output table
```

Expected total after Chapters 01 and 01a: seven approved private endpoints in `snet-zava-privateendpoints`.

### 10.12 Validate managed-identity roles

```powershell
az role assignment list `
  --assignee $projectMi `
  --all `
  --query '[].{role:roleDefinitionName,scope:scope}' `
  --output table

az cosmosdb sql role assignment list `
  --resource-group $workloadRg `
  --account-name $cosmos `
  --query "[?principalId=='$projectMi'].{principalId:principalId,roleDefinitionId:roleDefinitionId,scope:scope}" `
  --output table
```

Expected ARM roles:

- Storage Blob Data Owner
- Cosmos DB Operator
- Search Index Data Contributor
- Search Service Contributor

Also expect a Cosmos DB SQL data-plane assignment for the project identity.

### 10.13 Validate project connections

```powershell
az rest `
  --method GET `
  --url "https://management.azure.com${stdId}/projects/${stdProject}/connections?api-version=2025-06-01" `
  --query 'value[].{name:name,category:properties.category,auth:properties.authType,target:properties.target}' `
  --output table
```

Expected:

- `agent-storage` — `AzureStorageAccount` — `AAD`
- `agent-thread-storage` — `CosmosDB` — `AAD`
- `agent-vector-store` — `CognitiveSearch` — `AAD`

---

## 11. Mandatory private DNS checkpoint

Run these commands from a machine connected to `azr-133-eastus`, a peered VNet using Zava DNS, VPN, or ExpressRoute—not from an unrelated public workstation.

First run `ipconfig /all` and confirm the listed DNS servers are the Zava-approved resolver path. A VPN is sufficient only when it routes DNS queries for these Azure namespaces to Zava DNS. If any lookup returns a public address, times out, or resolves outside the private endpoint subnet, stop and ask the Zava DNS/network team to correct the zone group, VNet link/resolver, conditional forwarding, or routing.

```powershell
ipconfig /flushdns
nslookup "$stdFoundry.cognitiveservices.azure.com"
nslookup "$stdFoundry.openai.azure.com"
nslookup "$stdStorage.blob.core.windows.net"
nslookup "$cosmos.documents.azure.com"
nslookup "$search.search.windows.net"
```

Each service must resolve to an address in `10.75.139.144/28`.

Do not create capability hosts until:

- All four Chapter 01a private endpoints are approved.
- All five names resolve privately.
- All required project managed-identity roles are visible.
- All three AAD connections exist.

---

## 12. Deploy capability hosts once

Template:

- `05-chapter-01a-capability-hosts.bicep`

This stage creates:

1. Account capability host tied to `snet-zava-foundry-agent`
2. Project capability host tied to Storage, Cosmos DB, and Search connections

Capability-host creation is not reliably idempotent. Run this deployment only once.

### 12.1 Check that no hosts exist

```powershell
az rest `
  --method GET `
  --url "https://management.azure.com${stdId}/capabilityHosts?api-version=2025-06-01" `
  --query 'value[].{name:name,state:properties.provisioningState}' `
  --output table

az rest `
  --method GET `
  --url "https://management.azure.com${stdId}/projects/${stdProject}/capabilityHosts?api-version=2025-06-01" `
  --query 'value[].{name:name,state:properties.provisioningState}' `
  --output table
```

Both lists must be empty before first deployment.

### 12.2 Compile, validate, and preview

```powershell
az bicep build `
  --file .\infra\zava-chapter-01-01a-step-by-step\05-chapter-01a-capability-hosts.bicep

az deployment group validate `
  --resource-group $workloadRg `
  --name "zava-05-capability-hosts-$environment-validate" `
  --template-file .\infra\zava-chapter-01-01a-step-by-step\05-chapter-01a-capability-hosts.bicep `
  --parameters `
    workloadName=$workload `
    environment=$environment `
    networkResourceGroupName=$networkRg `
    vnetName=$vnet `
    agentSubnetName=$agentSubnet `
  --output none

az deployment group what-if `
  --resource-group $workloadRg `
  --name "zava-05-capability-hosts-$environment" `
  --template-file .\infra\zava-chapter-01-01a-step-by-step\05-chapter-01a-capability-hosts.bicep `
  --parameters `
    workloadName=$workload `
    environment=$environment `
    networkResourceGroupName=$networkRg `
    vnetName=$vnet `
    agentSubnetName=$agentSubnet `
  --result-format ResourceIdOnly
```

Expected: exactly two capability-host creations.

### 12.3 Deploy once

```powershell
az deployment group create `
  --resource-group $workloadRg `
  --name "zava-05-capability-hosts-$environment" `
  --template-file .\infra\zava-chapter-01-01a-step-by-step\05-chapter-01a-capability-hosts.bicep `
  --parameters `
    workloadName=$workload `
    environment=$environment `
    networkResourceGroupName=$networkRg `
    vnetName=$vnet `
    agentSubnetName=$agentSubnet `
  --output none
```

### 12.4 Validate both hosts

```powershell
az rest `
  --method GET `
  --url "https://management.azure.com${stdId}/capabilityHosts?api-version=2025-06-01" `
  --query 'value[].{name:name,state:properties.provisioningState,subnet:properties.customerSubnet}' `
  --output table

az rest `
  --method GET `
  --url "https://management.azure.com${stdId}/projects/${stdProject}/capabilityHosts?api-version=2025-06-01" `
  --query 'value[].{name:name,state:properties.provisioningState,storage:properties.storageConnections,threads:properties.threadStorageConnections,vectors:properties.vectorStoreConnections}' `
  --output json
```

Expected:

- Account capability host: `Succeeded`
- Project capability host: `Succeeded`
- Storage connection: `agent-storage`
- Thread connection: `agent-thread-storage`
- Vector connection: `agent-vector-store`

If one host fails or is missing, do not rerun the complete template. Inspect which host exists and recover only the missing resource.

### 12.5 Recover only a missing capability host

The folder contains `recover-capability-hosts.ps1`. It queries both host collections and creates only a missing host. It refuses to overwrite an existing failed host.

Capture the agent subnet resource ID:

```powershell
$agentSubnetId = az network vnet subnet show `
  --resource-group $networkRg `
  --vnet-name $vnet `
  --name $agentSubnet `
  --query id `
  --output tsv
```

Preview recovery without changing Azure:

```powershell
.\infra\zava-chapter-01-01a-step-by-step\recover-capability-hosts.ps1 `
  -Subscription $subscription `
  -TenantId $tenantId `
  -WorkloadResourceGroupName $workloadRg `
  -FoundryAccountName $stdFoundry `
  -FoundryProjectName $stdProject `
  -AgentSubnetResourceId $agentSubnetId `
  -WhatIf
```

Create only a missing host:

```powershell
.\infra\zava-chapter-01-01a-step-by-step\recover-capability-hosts.ps1 `
  -Subscription $subscription `
  -TenantId $tenantId `
  -WorkloadResourceGroupName $workloadRg `
  -FoundryAccountName $stdFoundry `
  -FoundryProjectName $stdProject `
  -AgentSubnetResourceId $agentSubnetId `
  -Confirm
```

If an existing host reports `Failed`, do not delete or overwrite it. Retrieve its complete ARM response, deployment operation errors, and activity-log correlation ID. Correct an explicit DNS/RBAC issue if shown; otherwise open a Microsoft support case.

---

## 13. Deploy the approved model separately

Deploy the model only after both capability hosts report `Succeeded`.

Set Zava-approved values:

```powershell
$modelDeployment = '<approved-deployment-name>'
$modelName       = '<approved-model-name>'
$modelVersion    = '<approved-model-version>'
$modelCapacity   = <approved-capacity>
```

Deploy:

```powershell
az cognitiveservices account deployment create `
  --resource-group $workloadRg `
  --name $stdFoundry `
  --deployment-name $modelDeployment `
  --model-name $modelName `
  --model-version $modelVersion `
  --model-format OpenAI `
  --sku-name GlobalStandard `
  --sku-capacity $modelCapacity `
  --output none
```

Validate:

```powershell
az cognitiveservices account deployment list `
  --resource-group $workloadRg `
  --name $stdFoundry `
  --query '[].{name:name,model:properties.model.name,version:properties.model.version,state:properties.provisioningState,sku:sku.name,capacity:sku.capacity}' `
  --output table
```

Expected state: `Succeeded`.

---

## 14. Final private data-plane test

Run from a VNet-connected administrative host:

1. Open the Standard Foundry project—not the Chapter 01 basic project.
2. Confirm the Agents page loads through private connectivity.
3. Create a temporary prompt agent using the approved model.
4. Start a thread and send a basic prompt.
5. Confirm a successful model response.
6. Confirm the project can use Storage, Cosmos DB, and Search without public access.
7. Delete the temporary agent if it is not needed.

Do not create production agents until network injection, capability hosts, DNS, and state-service connectivity are confirmed.

---

# Final acceptance checklist

## Customer network

- [ ] Zava confirmed `dmzsubnet-1` is `10.75.139.128/29`
- [ ] Existing DMZ subnet is unchanged
- [ ] Existing hybrid subnet is unchanged
- [ ] Private endpoint subnet is `10.75.139.144/28`
- [ ] Agent subnet is `10.75.139.160/27`
- [ ] Agent subnet is delegated to `Microsoft.App/environments`
- [ ] Agent subnet is exclusive to the Standard Foundry account

## DNS

- [ ] Seven customer private DNS zones exist
- [ ] Seven zones resolve through Zava's DNS architecture
- [ ] VNet links or equivalent Private Resolver forwarding are configured
- [ ] Foundry, Storage, Key Vault, Cosmos DB, and Search resolve privately

## Chapter 01

- [ ] Basic Foundry account succeeded
- [ ] Basic Foundry project succeeded
- [ ] Storage public access and shared keys are disabled
- [ ] Key Vault public access is disabled and RBAC is enabled
- [ ] Three private endpoints are approved

## Chapter 01a

- [ ] Standard Foundry account succeeded
- [ ] `networkInjections` references `snet-zava-foundry-agent`
- [ ] `useMicrosoftManagedNetwork` is `false`
- [ ] Standard Foundry project succeeded
- [ ] Agent Storage succeeded and is private
- [ ] Cosmos DB succeeded and is private
- [ ] Azure AI Search succeeded and is private
- [ ] Four Chapter 01a private endpoints are approved
- [ ] Project managed-identity roles are present
- [ ] Three AAD project connections are present
- [ ] Account capability host succeeded
- [ ] Project capability host succeeded
- [ ] Approved model deployment succeeded
- [ ] Temporary agent completed a private-path test
