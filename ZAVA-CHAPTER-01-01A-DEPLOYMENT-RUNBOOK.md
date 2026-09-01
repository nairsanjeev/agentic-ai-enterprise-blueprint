# Zava Deployment Runbook — Chapters 01 and 01a

This runbook covers deploying Chapters 01 and 01a into a Zava subscription while Zava owns the VNet, subnets, routing, firewall, private DNS, and other networking controls.

> **Important:** Do not deploy the current templates unchanged. They currently create or assume ownership of some private DNS resources, and Chapter 01a assumes the VNet is in the workload resource group. Complete the template-readiness changes below first.

---

## 1. Target architecture

Zava provides and manages:

- Azure subscription and workload resource group
- Existing VNet
- Dedicated Foundry agent subnet
- Dedicated private endpoint subnet
- Routing, NSGs, firewall, and outbound controls
- Private DNS zones, links, resolvers, and forwarding
- A VNet-connected host for data-plane testing

The deployment creates:

### Chapter 01

- Private Microsoft Foundry account and project
- Private Storage account
- Private Key Vault
- Private endpoints for Foundry, Blob Storage, and Key Vault
- Optional model deployment

### Chapter 01a

- A separate Standard Foundry account and project
- Foundry agent network injection
- Customer-owned Storage for agent files
- Cosmos DB for agent threads and messages
- Azure AI Search for vector stores
- Four private endpoints
- Project connections and capability hosts
- Managed-identity role assignments
- Optional model deployment

The Chapter 01a Standard account is the production target for agents that must reach private Zava services.

---

## 2. Information required from Zava

Obtain this information before deployment:

```text
Tenant ID:
Tenant primary domain:
Subscription ID:
Subscription name:

Workload resource group:
Approved Azure region:
Approved workload name:
Environment: dev, test, or prod

Network resource group:
VNet name:
VNet resource ID:

Foundry agent subnet name:
Foundry agent subnet resource ID:
Foundry agent subnet CIDR:

Private endpoint subnet name:
Private endpoint subnet resource ID:
Private endpoint subnet CIDR:

Custom DNS servers configured on VNet:
Azure Private Resolver inbound endpoint:
VNet-connected administrative VM or jumpbox:

Private DNS zone resource IDs:
- privatelink.cognitiveservices.azure.com
- privatelink.openai.azure.com
- privatelink.services.ai.azure.com
- privatelink.blob.core.windows.net
- privatelink.vaultcore.azure.net
- privatelink.documents.azure.com
- privatelink.search.windows.net

Team responsible for private endpoint approval:
Team responsible for private endpoint DNS-zone groups:
Team responsible for DNS validation:

Approved model name and version:
Approved GlobalStandard capacity:
Approved Azure AI Search region:
```

---

## 3. Zava network prerequisites

### Foundry agent subnet

Zava must provide a dedicated subnet with:

- Delegation to `Microsoft.App/environments`
- Recommended size of `/24`
- No private endpoints in the subnet
- No conflicting service delegation
- DNS access to Zava private zones
- Routes, NSGs, and firewall rules compatible with Foundry agent network injection
- Required outbound access to Azure platform and Microsoft Entra endpoints

Validation:

```powershell
$networkRg = '<Zava-network-resource-group>'
$vnet      = '<Zava-vnet-name>'
$agentSnet = '<Zava-foundry-agent-subnet>'

az network vnet subnet show `
  --resource-group $networkRg `
  --vnet-name $vnet `
  --name $agentSnet `
  --query '{id:id,prefix:addressPrefix,delegations:delegations[].serviceName,policies:privateEndpointNetworkPolicies}' `
  --output json
```

Expected delegation: `Microsoft.App/environments`.

### Private endpoint subnet

Zava must provide a separate subnet that permits private endpoints. Deploying both chapters creates seven private endpoints:

1. Chapter 01 Foundry
2. Chapter 01 Storage
3. Chapter 01 Key Vault
4. Chapter 01a Standard Foundry
5. Chapter 01a Storage
6. Chapter 01a Cosmos DB
7. Chapter 01a Azure AI Search

Allow extra capacity for future services.

Validation:

```powershell
$peSnet = '<Zava-private-endpoint-subnet>'

az network vnet subnet show `
  --resource-group $networkRg `
  --vnet-name $vnet `
  --name $peSnet `
  --query '{id:id,prefix:addressPrefix,privateEndpointNetworkPolicies:privateEndpointNetworkPolicies}' `
  --output json
```

---

## 4. Zava private DNS prerequisites

Zava must provide these private DNS zones or equivalent centrally managed resolution:

| Service | Private DNS zone |
|---|---|
| Foundry/Azure AI Services | `privatelink.cognitiveservices.azure.com` |
| Azure OpenAI | `privatelink.openai.azure.com` |
| Foundry project services | `privatelink.services.ai.azure.com` |
| Blob Storage | `privatelink.blob.core.windows.net` |
| Key Vault | `privatelink.vaultcore.azure.net` |
| Cosmos DB for NoSQL | `privatelink.documents.azure.com` |
| Azure AI Search | `privatelink.search.windows.net` |

Recommended design:

1. Zava hosts the private DNS zones centrally.
2. Zones are linked to the workload VNet or reachable through Azure Private Resolver.
3. Custom/on-premises DNS conditionally forwards the private zones to the Azure resolver.
4. Private endpoint DNS-zone groups register records in the approved zones.
5. Zava validates resolution from a VNet-connected host.

VNet peering alone does not provide private DNS resolution.

### DNS ownership options

**Recommended — deployment attaches customer zones:** Zava supplies zone resource IDs and grants narrowly scoped permission to create private endpoint DNS-zone groups. The deployment does not create or link zones.

**Alternative — Zava completes all DNS associations:** The deployment creates private endpoints without DNS-zone groups. Zava creates the zone groups or records afterward. Chapter 01a capability-host provisioning must wait until Storage, Cosmos DB, and Search resolve privately.

---

## 5. Required Azure access

### Workload resource group

The deployment identity needs:

- `Contributor`
- `User Access Administrator` or `Role Based Access Control Administrator`

The second role is required because Chapter 01a creates role assignments for the Foundry project managed identity.

### Network scope

The deployment identity needs subnet read and join access on both supplied subnets. A temporary `Network Contributor` assignment at the VNet or subnet scope is the simplest option.

Access to the workload resource group does not grant access to a VNet in another resource group.

### DNS scope

- If the deployment creates DNS-zone groups, grant the required association permissions on the customer zones.
- If Zava performs the associations, no DNS write access is required by the deployment identity.

### Resource providers

Zava must pre-register these providers because an RG-scoped identity normally cannot register them:

- `Microsoft.App`
- `Microsoft.CognitiveServices`
- `Microsoft.ContainerService`
- `Microsoft.DocumentDB`
- `Microsoft.KeyVault`
- `Microsoft.Network`
- `Microsoft.Search`
- `Microsoft.Storage`

Check registration:

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
    --query '{Provider:namespace,State:registrationState}' `
    --output table
}
```

Zava registers any missing provider:

```powershell
foreach ($provider in $providers) {
  az provider register --namespace $provider
}
```

---

## 6. Template-readiness changes required

Before the customer deployment:

1. Change Chapter 01 to reference customer-owned private DNS zones rather than create zones and VNet links.
2. Change Chapter 01a to reference customer-owned Foundry, Blob, Cosmos DB, and Search private DNS zones.
3. Add an existing VNet resource-group parameter to Chapter 01a.
4. Update the Chapter 01a script so its VNet check supports a separate networking resource group.
5. Stop both scripts from attempting provider registration when Zava owns subscription administration.
6. Replace the Chapter 01a tenant email-suffix check with tenant-ID validation because guest identities can contain `#EXT#`.
7. Correct Chapter 01's final subnet check so it uses the supplied network RG, VNet, and subnet names.
8. Ensure what-if shows no VNet, subnet, route-table, NSG, private DNS zone, or VNet-link changes.

---

## 7. Capacity and policy checks

Zava should confirm:

- `AIServices` accounts are permitted by Azure Policy.
- Private endpoints are permitted in the supplied subnet.
- System-assigned managed identities are permitted.
- The deployment identity may create role assignments.
- Storage, Key Vault, Cosmos DB, Search, and Foundry may disable public access.
- Azure AI Search Standard capacity exists in the selected region.
- The selected model and version are available.
- Global Standard quota is available for the requested model capacity.
- Mandatory naming and tagging requirements are known.
- Zava accepts two Foundry accounts while both chapters coexist.

---

## 8. Deployment steps

Run from the repository root in PowerShell after the readiness changes are complete.

### Step 1 — Set customer values and sign in

```powershell
$tenantId       = '<Zava-tenant-id>'
$subscriptionId = '<Zava-subscription-id>'
$workloadRg     = '<Zava-workload-resource-group>'
$location       = '<approved-region>'
$networkRg      = '<Zava-network-resource-group>'
$vnet           = '<Zava-vnet-name>'
$agentSubnet    = '<Zava-foundry-agent-subnet>'
$peSubnet       = '<Zava-private-endpoint-subnet>'
$workload       = '<approved-short-workload-name>'
$environment    = 'dev'

az login --tenant $tenantId --use-device-code
az account set --subscription $subscriptionId
az account show `
  --query '{subscription:name,subscriptionId:id,tenantId:tenantId,user:user.name}' `
  --output table
```

Stop unless the subscription ID and tenant ID are correct.

### Step 2 — Verify the resource group and VNet

```powershell
az group show --name $workloadRg --output table

az network vnet show `
  --resource-group $networkRg `
  --name $vnet `
  --query '{id:id,location:location,addressSpace:addressSpace.addressPrefixes}' `
  --output json

az network vnet subnet show `
  --resource-group $networkRg `
  --vnet-name $vnet `
  --name $agentSubnet `
  --query '{id:id,prefix:addressPrefix,delegations:delegations[].serviceName}' `
  --output json

az network vnet subnet show `
  --resource-group $networkRg `
  --vnet-name $vnet `
  --name $peSubnet `
  --query '{id:id,prefix:addressPrefix,privateEndpointNetworkPolicies:privateEndpointNetworkPolicies}' `
  --output json
```

### Step 3 — Compile the Bicep templates

```powershell
az bicep build `
  --file .\infra\chapter-01-foundry-byo-networking\main.bicep

az bicep build `
  --file .\infra\chapter-01a-standard-agent-network-injection\main.bicep
```

Do not continue if compilation reports errors.

### Step 4 — Preview Chapter 01

Deploy infrastructure without a model first:

```powershell
.\infra\chapter-01-foundry-byo-networking\deploy.ps1 `
  -SubscriptionName $subscriptionId `
  -Tenant $tenantId `
  -ResourceGroupName $workloadRg `
  -Location $location `
  -WorkloadName $workload `
  -Environment $environment `
  -ExistingVnetName $vnet `
  -ExistingVnetResourceGroupName $networkRg `
  -FoundrySubnetName $agentSubnet `
  -PrivateEndpointSubnetName $peSubnet `
  -DeployModel:$false
```

Review the what-if output with Zava. It must show:

- No VNet or subnet creation
- No VNet or subnet modification
- No customer DNS zone or VNet-link creation
- No route-table, NSG, or firewall changes
- No unexpected deletions
- Only approved workload resources and private endpoints

### Step 5 — Execute Chapter 01

```powershell
.\infra\chapter-01-foundry-byo-networking\deploy.ps1 `
  -SubscriptionName $subscriptionId `
  -Tenant $tenantId `
  -ResourceGroupName $workloadRg `
  -Location $location `
  -WorkloadName $workload `
  -Environment $environment `
  -ExistingVnetName $vnet `
  -ExistingVnetResourceGroupName $networkRg `
  -FoundrySubnetName $agentSubnet `
  -PrivateEndpointSubnetName $peSubnet `
  -DeployModel:$false `
  -Execute
```

### Step 6 — Chapter 01 DNS checkpoint

Zava associates the private endpoints with:

- Foundry PE: three Foundry private DNS zones
- Storage PE: Blob private DNS zone
- Key Vault PE: Key Vault private DNS zone

Get the resource names:

```powershell
$foundry = az deployment group show `
  --resource-group $workloadRg `
  --name chapter-01-$environment `
  --query 'properties.outputs.foundryAccountName.value' `
  --output tsv

$storage = az deployment group show `
  --resource-group $workloadRg `
  --name chapter-01-$environment `
  --query 'properties.outputs.storageAccountName.value' `
  --output tsv

$vault = az deployment group show `
  --resource-group $workloadRg `
  --name chapter-01-$environment `
  --query 'properties.outputs.keyVaultName.value' `
  --output tsv
```

From a VNet-connected host:

```powershell
nslookup "$foundry.cognitiveservices.azure.com"
nslookup "$foundry.openai.azure.com"
nslookup "$storage.blob.core.windows.net"
nslookup "$vault.vault.azure.net"
```

All names must resolve through the approved Zava DNS path to private addresses.

### Step 7 — Preview Chapter 01a

After adding the network resource-group parameter to Chapter 01a:

```powershell
.\infra\chapter-01a-standard-agent-network-injection\deploy.ps1 `
  -SubscriptionName $subscriptionId `
  -Tenant $tenantId `
  -ResourceGroupName $workloadRg `
  -Location $location `
  -WorkloadName $workload `
  -Environment $environment `
  -ExistingVnetName $vnet `
  -ExistingVnetResourceGroupName $networkRg `
  -AgentSubnetName $agentSubnet `
  -PrivateEndpointSubnetName $peSubnet `
  -DeployModel:$false
```

The preview should contain:

- Standard Foundry account and project
- Storage, Cosmos DB, and AI Search
- Four private endpoints
- Three project connections
- Account and project capability hosts
- Managed-identity role assignments
- No customer network or DNS changes

### Step 8 — Execute Chapter 01a once

```powershell
.\infra\chapter-01a-standard-agent-network-injection\deploy.ps1 `
  -SubscriptionName $subscriptionId `
  -Tenant $tenantId `
  -ResourceGroupName $workloadRg `
  -Location $location `
  -WorkloadName $workload `
  -Environment $environment `
  -ExistingVnetName $vnet `
  -ExistingVnetResourceGroupName $networkRg `
  -AgentSubnetName $agentSubnet `
  -PrivateEndpointSubnetName $peSubnet `
  -DeployModel:$false `
  -Execute
```

> Do not blindly rerun Chapter 01a after a partial failure. Capability-host creation is not reliably idempotent. Inspect the account and project capability hosts before recovery.

### Step 9 — Chapter 01a DNS checkpoint

Zava associates:

- Standard Foundry PE: three Foundry zones
- Storage PE: Blob zone
- Cosmos DB PE: Cosmos DB zone
- Search PE: Search zone

Get the names:

```powershell
$stdFoundry = az deployment group show `
  --resource-group $workloadRg `
  --name chapter-01a-$environment `
  --query 'properties.outputs.foundryAccountName.value' `
  --output tsv

$stdProject = az deployment group show `
  --resource-group $workloadRg `
  --name chapter-01a-$environment `
  --query 'properties.outputs.foundryProjectName.value' `
  --output tsv

$stdStorage = az deployment group show `
  --resource-group $workloadRg `
  --name chapter-01a-$environment `
  --query 'properties.outputs.storageAccountName.value' `
  --output tsv

$cosmos = az deployment group show `
  --resource-group $workloadRg `
  --name chapter-01a-$environment `
  --query 'properties.outputs.cosmosAccountName.value' `
  --output tsv

$search = az deployment group show `
  --resource-group $workloadRg `
  --name chapter-01a-$environment `
  --query 'properties.outputs.searchServiceName.value' `
  --output tsv
```

From the VNet-connected host:

```powershell
nslookup "$stdFoundry.cognitiveservices.azure.com"
nslookup "$stdFoundry.openai.azure.com"
nslookup "$stdStorage.blob.core.windows.net"
nslookup "$cosmos.documents.azure.com"
nslookup "$search.search.windows.net"
```

All names must resolve to private addresses.

### Step 10 — Verify network injection

```powershell
$stdAccountId = az resource show `
  --resource-group $workloadRg `
  --name $stdFoundry `
  --resource-type Microsoft.CognitiveServices/accounts `
  --query id `
  --output tsv

az rest `
  --method GET `
  --url "https://management.azure.com${stdAccountId}?api-version=2025-06-01" `
  --query 'properties.networkInjections' `
  --output json
```

Expected values:

- `scenario` is `agent`
- `subnetArmId` is the supplied Zava Foundry subnet
- `useMicrosoftManagedNetwork` is `false`

### Step 11 — Verify capability hosts

```powershell
az rest `
  --method GET `
  --url "https://management.azure.com${stdAccountId}/capabilityHosts?api-version=2025-06-01" `
  --query 'value[].{name:name,state:properties.provisioningState}' `
  --output table

az rest `
  --method GET `
  --url "https://management.azure.com${stdAccountId}/projects/${stdProject}/capabilityHosts?api-version=2025-06-01" `
  --query 'value[].{name:name,state:properties.provisioningState,storage:properties.storageConnections,threads:properties.threadStorageConnections,vectors:properties.vectorStoreConnections}' `
  --output json
```

Both capability hosts must report `Succeeded`. The project capability host must contain Storage, thread Storage, and vector Store connections.

### Step 12 — Verify private endpoints

```powershell
az network private-endpoint list `
  --resource-group $workloadRg `
  --query '[].{Name:name,Status:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status,Subnet:subnet.id}' `
  --output table
```

All private endpoints must be approved and attached to the supplied Zava private endpoint subnet.

### Step 13 — Deploy the approved model

Deploy the model only after infrastructure, DNS, private endpoints, and capability hosts are healthy:

```powershell
az cognitiveservices account deployment create `
  --resource-group $workloadRg `
  --name $stdFoundry `
  --deployment-name '<approved-deployment-name>' `
  --model-name '<approved-model-name>' `
  --model-version '<approved-model-version>' `
  --model-format OpenAI `
  --sku-name GlobalStandard `
  --sku-capacity <approved-capacity>
```

For production agents, deploy the model on the Chapter 01a Standard account. Avoid duplicate model deployments on both accounts unless Chapter 01 specifically requires one.

### Step 14 — Private data-plane acceptance test

From a Zava VNet-connected host:

1. Open the Standard Foundry project.
2. Create a temporary prompt agent.
3. Run a basic model interaction.
4. Verify thread/message activity uses the customer Cosmos DB.
5. Verify agent files use customer Storage.
6. Verify vector-store operations use customer Search.
7. Call an approved private test endpoint.
8. Confirm the endpoint receives traffic through the Zava network path.
9. Remove the temporary agent after acceptance.

---

## 9. Go/no-go checklist

- [ ] Correct Zava tenant and subscription confirmed
- [ ] Workload resource group exists
- [ ] Required resource providers are registered
- [ ] Azure Policy preflight completed
- [ ] Model availability and quota confirmed
- [ ] Azure AI Search capacity confirmed
- [ ] VNet region is compatible with Foundry
- [ ] Agent subnet is delegated to `Microsoft.App/environments`
- [ ] Separate private endpoint subnet is available
- [ ] Deployment identity has subnet read and join permission
- [ ] Seven customer private DNS zones or equivalent resolution are available
- [ ] DNS association ownership is agreed
- [ ] Private Resolver and conditional forwarding are configured
- [ ] VNet-connected validation host is available
- [ ] Templates reference rather than create customer DNS
- [ ] Chapter 01a supports the network resource group
- [ ] What-if has been reviewed and approved by Zava
- [ ] No VNet, subnet, route-table, NSG, firewall, DNS-zone, or VNet-link changes appear
- [ ] Rollback and cleanup ownership is agreed
- [ ] Decision to retain or retire the Chapter 01 account is documented

---

# Customer talk track

## Opening

> We are deploying a private Microsoft Foundry Standard Agent environment into Zava's existing Azure network. Zava remains the owner of the VNet, routing, firewall policy, private DNS, and private endpoint governance. Our deployment owns only the AI workload resources in the approved workload resource group.

## Network boundaries

> We need two existing subnets. The first is dedicated and delegated to Microsoft.App/environments so Foundry can inject hosted agent execution into Zava's network. The second hosts private endpoints. We will not create or change the VNet, address space, routing, NSGs, firewall, or DNS links.

## Why there are two chapters

> Chapter 01 establishes the original private Foundry foundation with private Storage and Key Vault. Chapter 01a creates a separate Standard Foundry account with full agent network injection and customer-owned Storage, Cosmos DB, and Azure AI Search. The Standard account is the production target for agents that must call private Zava services.

## Why a second Foundry account is required

> Network injection must be configured before agents are created, and an existing agent environment should not be converted in place. The safer pattern is to create a new Standard account, validate it, rebuild agents there, and then decide whether the original Chapter 01 account should be retired.

## DNS ownership

> Each service retains its standard Azure hostname, while Zava-managed private DNS resolves that hostname to the private endpoint address. Zava owns the zones and forwarding path. The deployment will reference approved zones or pause after endpoint creation so the Zava DNS team can complete the associations.

## Security posture

> Public network access is disabled for Foundry, Storage, Key Vault, Cosmos DB, and Azure AI Search. Local keys and shared-key authentication are disabled where supported. Foundry authenticates to customer-owned state services with a managed identity and narrowly scoped Azure roles.

## Data ownership

> Agent files are stored in Zava Storage. Agent threads and messages are stored in Zava Cosmos DB. Vector stores are held in Zava Azure AI Search. These services remain in the Zava subscription and are reachable through private endpoints.

## Deployment controls

> The first deployment run performs validation and what-if only. Zava reviews the exact resource changes before execution. We will not proceed if the preview shows changes to the customer VNet, subnets, route tables, NSGs, DNS zones, DNS links, or firewall configuration.

## Validation

> Validation occurs in two stages. First, we validate the Azure control plane: resource state, private endpoint approval, managed identities, role assignments, network injection, and capability hosts. Second, from a Zava VNet-connected host, the network team validates private DNS and the application team performs a private model and agent test.

## Responsibility split

> Our team owns the Bicep deployment, Foundry resources, managed identities, capability hosts, and workload validation. Zava owns subscription provider registration, network readiness, DNS, private endpoint policy, routing, firewall rules, and final network approval.

## Acceptance criteria

> The deployment is accepted when there are no unintended network changes, all service public access is disabled, every service resolves privately, both capability hosts succeed, managed-identity access works, and a test agent executes through the injected Zava network path.
