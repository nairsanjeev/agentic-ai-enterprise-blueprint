# Zava Customer Deployment from VS Code

This is the recommended customer-side experience when GitHub Copilot agent mode is unavailable. It uses native VS Code tasks, Azure CLI, PowerShell 7, and the existing Bicep stages.

## 1. Install prerequisites

Install locally:

- Visual Studio Code
- Azure CLI
- PowerShell 7
- VS Code Bicep extension
- VS Code PowerShell extension
- VS Code Azure Account extension

When this repository opens, VS Code reads `.vscode/extensions.json` and recommends the free extensions.

Verify in a VS Code terminal:

```powershell
az version
az bicep version
pwsh --version
```

## 2. Clone and open the repository

```powershell
git clone https://github.com/nairsanjeev/agentic-ai-enterprise-blueprint.git
Set-Location agentic-ai-enterprise-blueprint
code .
```

Use the `master` branch unless the customer has an approved release branch.

## 3. Create the customer-local configuration

Copy the example. The populated file is ignored by Git.

```powershell
Copy-Item `
  .\infra\zava-chapter-01-01a-step-by-step\zava.customer.example.json `
  .\infra\zava-chapter-01-01a-step-by-step\zava.customer.json
```

Edit `zava.customer.json` and replace every placeholder:

| Property | Exact meaning |
|---|---|
| `tenantId` | Zava Microsoft Entra tenant GUID |
| `subscription` | Target workload subscription ID or exact name |
| `workloadResourceGroupName` | Resource group for Foundry and supporting services |
| `networkResourceGroupName` | Resource group containing `azr-133-eastus` |
| `privateDnsResourceGroupName` | Resource group containing the seven central private DNS zones |
| `location` | `eastus`; must match the VNet for Foundry |
| `searchLocation` | Approved AI Search region; usually `eastus` |
| `vnetName` | `azr-133-eastus` |
| `agentSubnetName` | `snet-zava-foundry-agent` |
| `agentSubnetPrefix` | `10.75.139.160/27` |
| `privateEndpointSubnetName` | `snet-zava-privateendpoints` |
| `privateEndpointSubnetPrefix` | `10.75.139.144/28` |
| `createPrivateEndpointDnsZoneGroups` | `true` only when the deployment identity may associate PEs with central zones; otherwise `false` |
| `foundryUserObjectId` | Approved Entra user object ID; blank defaults to the signed-in user |
| Model properties | Zava-approved deployment, model, version, and capacity |

Before proceeding, obtain written confirmation that the supplied DMZ range means `10.75.139.128/29`. The originally supplied `10.75.128/29` is outside the VNet address space.

## 4. Sign in

From the VS Code terminal:

```powershell
az login --tenant <Zava-tenant-id> --use-device-code
az account set --subscription <Zava-subscription-id-or-name>
az account show --query '{name:name,id:id,tenantId:tenantId,user:user.name}' -o table
```

Stop if the subscription or tenant is incorrect.

## 5. Open the task picker

Use:

- **Terminal → Run Task**
- Or press **Ctrl+Shift+P**, enter **Tasks: Run Task**

When prompted for the configuration path, accept the default path to `zava.customer.json` or enter another approved configuration path.

## 6. Stage 01 — Foundry subnets

Run these tasks in order:

1. `Zava: 01 - Preview Subnets`
2. Review the what-if. It must create only:
   - `snet-zava-privateendpoints` — `10.75.139.144/28`
   - `snet-zava-foundry-agent` — `10.75.139.160/27`
3. Stop if it modifies or deletes `dmzsubnet-1`, `hybridsubnet-1`, the VNet address space, routes, NSGs, or peerings.
4. Run `Zava: 01 - Deploy Subnets` only after approval.

The agent subnet is delegated to `Microsoft.App/environments`. The PE subnet has private endpoint policies disabled.

## 7. Stage 02 — DNS links, only if applicable

Determine Zava's DNS topology first:

- **Direct spoke links:** run both Stage 02 tasks.
- **Central hub resolver:** skip Stage 02. Zava DNS must ensure the spoke resolves the private namespaces through the hub resolver.

For direct links:

1. Run `Zava: 02 - Preview Direct DNS Links`.
2. Expected: seven VNet link creations and no zone deletion/modification.
3. Run `Zava: 02 - Deploy Direct DNS Links` after DNS-team approval.

Required central zones:

- `privatelink.cognitiveservices.azure.com`
- `privatelink.openai.azure.com`
- `privatelink.services.ai.azure.com`
- `privatelink.blob.core.windows.net`
- `privatelink.vaultcore.azure.net`
- `privatelink.documents.azure.com`
- `privatelink.search.windows.net`

## 8. Stage 03 — Chapter 01 foundation

Run:

1. `Zava: 03 - Preview Chapter 01`
2. Verify it creates only the approved Basic Foundry account/project, Storage, Key Vault, three private endpoints, DNS-zone groups if enabled, and Foundry User assignment.
3. Verify it does not modify customer VNet, subnets, DNS zones, VNet links, routing, NSGs, or firewalls.
4. Run `Zava: 03 - Deploy Chapter 01`.

Chapter 01 does not deploy a model. Production network-injected agents use the Standard account from Stage 04.

## 9. Stage 04 — Chapter 01a Standard core

Run:

1. `Zava: 04 - Preview Chapter 01a Core`
2. Expected resources:
   - Standard network-injected Foundry account/project
   - Private agent Storage
   - Private Cosmos DB
   - Private Azure AI Search
   - Four private endpoints
   - Project identity roles
   - Three AAD project connections
3. Confirm no customer network or DNS-zone ownership changes.
4. Run `Zava: 04 - Deploy Chapter 01a Core`.

Before continuing, validate from a Zava-connected host that Foundry, Blob, Cosmos DB, and Search resolve to addresses in `10.75.139.144/28`. Also verify all four private endpoints are approved.

## 10. Stage 05 — Capability hosts, one time only

Capability hosts are not reliably idempotent.

1. Ensure account and project capability-host collections are empty.
2. Confirm DNS, private endpoints, roles, and all three connections are healthy.
3. Run `Zava: 05 - Preview Capability Hosts`.
4. Expected: exactly one account capability host and one project capability host.
5. Run `Zava: 05 - Deploy Capability Hosts ONCE` exactly once.
6. Verify both hosts reach `Succeeded` before creating agents or deploying the model.

If a partial failure occurs, do not rerun the combined task. Use `recover-capability-hosts.ps1` according to the manual guide.

## 11. Stage 06 — Model

1. Populate the approved model values in `zava.customer.json`.
2. Run `Zava: 06 - Review Model`.
3. Confirm regional model availability and quota.
4. Run `Zava: 06 - Deploy Model`.
5. Verify the deployment reaches `Succeeded`.

## 12. Direct command format

Tasks call this wrapper. The same actions can be executed from a terminal:

```powershell
$configuration = '.\infra\zava-chapter-01-01a-step-by-step\zava.customer.json'

# Safe validation + what-if
.\infra\zava-chapter-01-01a-step-by-step\Invoke-ZavaCustomerDeployment.ps1 `
  -Configuration $configuration `
  -Stage Chapter01aCore `
  -Action Preview

# Deployment requires an explicit confirmation switch
.\infra\zava-chapter-01-01a-step-by-step\Invoke-ZavaCustomerDeployment.ps1 `
  -Configuration $configuration `
  -Stage Chapter01aCore `
  -Action Deploy `
  -ConfirmDeployment
```

Supported stage values:

- `Subnets`
- `DnsLinks`
- `Chapter01`
- `Chapter01aCore`
- `CapabilityHosts`
- `Model`

There is no customer `Deploy All` action. Every stage must be previewed and approved independently.

## 13. Important current boundary

The Bicep templates support separate workload, network, and DNS resource groups **within the selected subscription**. If the VNet or central DNS zones are in another subscription, add explicit network/DNS subscription ID parameters and grant cross-subscription access before deployment. Do not assume resource-group parameters alone provide cross-subscription support.
