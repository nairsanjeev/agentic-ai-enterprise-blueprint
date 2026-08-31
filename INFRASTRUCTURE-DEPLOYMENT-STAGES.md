# Infrastructure Deployment Stages and Required Permissions

This document maps the deployable infrastructure in this repository to its chapter, deployment order, Bicep template, prerequisites, and Azure permissions.

> **Scope:** The repository currently contains seven Bicep templates: Chapters 01, 01a, 02, 02a, 04, 06, and 15. Chapter 16 uses Azure CLI and Python rather than Bicep, and Chapter 16a is a demonstration runbook. The remaining chapters are architecture guidance or application/governance exercises and do not currently have deployable Bicep under `infra/`.

## 1. Recommended stage order

```text
Stage 0  Azure preparation
   |
Stage 1  Chapter 01 - Network and private Foundry foundation
   |\
   | +--> Stage 3 - Chapter 02 - AI gateway
   |          |\
   |          | +--> Stage 4A - Chapter 02a - MCP and A2A APIs
   |          +----> Stage 4B - Chapter 04 - API Center
   |
   +----> Stage 2 - Chapter 01a - Standard agent setup
                  |\
                  | +--> Stage 5 - Chapter 06 - Foundry IQ foundation
                  +----> Stage 6 - Chapter 15 - Observability and guardrails
                                      |
                                      +--> Stage 7 - Chapter 16 - Defender for AI
                                                |
                                                +--> Stage 8 - Chapter 16a demo
```

Chapters 02a and 04 can run in parallel after Chapter 02. Chapter 06 can run after Chapter 01a. Chapter 15 requires both Chapter 01a and Chapter 02.

## 2. Permission model

### Recommended deployment identity

For the simplest lab deployment, use one of these configurations:

1. **Owner** at the target resource-group scope, after the resource group exists and providers are registered; or
2. **Contributor** plus **Role Based Access Control Administrator** at the target resource-group scope. **User Access Administrator** can be used instead of Role Based Access Control Administrator.

`Contributor` alone is **not sufficient** for Chapters 01, 01a, 02, or 04 because those templates create Azure RBAC role assignments. Contributor deliberately excludes `Microsoft.Authorization/roleAssignments/write`.

For least privilege in an enterprise pipeline, separate the duties:

- A subscription administrator creates the resource group and registers resource providers.
- The deployment identity receives Contributor on the deployment resource group.
- For stages that create RBAC, the identity also receives Role Based Access Control Administrator on that resource group, preferably with an assignment condition restricting the roles it may grant.
- A security administrator separately enables Defender for AI in Chapter 16.

### Subscription preparation versus resource-group deployment

| Operation | Required scope | Permission or typical role |
|---|---|---|
| Create the resource group in Chapter 01 | Subscription | `Microsoft.Resources/subscriptions/resourceGroups/write`; Resource Group Contributor, Contributor, or Owner |
| Register resource providers | Subscription | `Microsoft.Resources/providers/register/action`; Contributor/Owner at subscription or a custom provider-registration role |
| Run `az deployment group validate`, `what-if`, and `create` | Resource group | Contributor is the safe baseline |
| Create template RBAC assignments | Scope of the assignment or a parent scope | `Microsoft.Authorization/roleAssignments/write`; Role Based Access Control Administrator, User Access Administrator, or Owner |
| Read role definitions | Assignment scope or parent | `Microsoft.Authorization/roleDefinitions/read` |
| Enable Defender for AI | Subscription | `Microsoft.Security/pricings/write`; Security Admin or equivalent custom role |

If all required providers are already registered, the deployment runner does not need provider-registration permission. The supplied wrappers still call provider registration in Chapters 01, 01a, 02, and 04, so either grant the permission or modify the operational process to pre-register providers and omit those calls.

### Service principal note

Several wrappers default a human principal parameter by running `az ad signed-in-user show`. A service principal should pass `-FoundryUserObjectId` or `-CatalogReaderObjectId` explicitly. Optional Entra app creation in Chapter 04 requires Microsoft Graph application permissions and is separate from Azure RBAC.

### Customer resource-group deployment requirements (Chapter 01a)

When Chapter 01a is deployed into an **existing customer-owned resource group**, request the following access for the human user, service principal, or workload identity running the deployment.

#### Access required on the customer resource group

Grant both roles at the target resource-group scope:

1. **Contributor** — creates and updates the Foundry account/project, Storage, Cosmos DB, AI Search, private endpoints, private DNS resources, connections, capability hosts, model deployment, and ARM deployment records.
2. **Role Based Access Control Administrator** — creates the Azure RBAC assignments required by the template. **User Access Administrator** may be used instead.

**Owner** on the resource group also works but is broader than required. **Contributor alone does not work** because it excludes `Microsoft.Authorization/roleAssignments/write`.

Chapter 01a creates these assignments:

- Storage Blob Data Owner for the Foundry project identity.
- Cosmos DB Operator for the Foundry project identity.
- Search Index Data Contributor for the Foundry project identity.
- Search Service Contributor for the Foundry project identity.
- Optional Foundry User for the supplied user, group, or service principal.

The template also creates a Cosmos DB SQL Data Contributor assignment. This uses `Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments/write`, rather than Azure RBAC `roleAssignments/write`, and is covered by Contributor on the resource group.

For production least privilege, the customer can replace the two broad roles with custom roles containing only the resource actions used by the template and restrict which roles the deployment identity may assign with an Azure RBAC assignment condition.

#### Access or preparation required outside the resource group

| External requirement | Required access or customer action |
|---|---|
| Resource providers | A subscription administrator pre-registers `Microsoft.App`, `Microsoft.CognitiveServices`, `Microsoft.DocumentDB`, `Microsoft.KeyVault`, `Microsoft.Network`, `Microsoft.Search`, and `Microsoft.Storage`; otherwise the runner needs `Microsoft.Resources/providers/register/action` at subscription scope. |
| Existing network in another resource group | Reader plus the required VNet/subnet join permission on the VNet and subnets; Network Contributor is the simpler but broader alternative. The current Chapter 01a template assumes its primary VNet, subnets, and existing private DNS zones are in the deployment resource group, so cross-resource-group primary-network reuse requires a template change. |
| Additional linked VNets | Reader and `Microsoft.Network/virtualNetworks/join/action` on each external VNet referenced through `additionalLinkedVnetIds`. The runner must also be allowed to create the private DNS virtual-network link in the deployment resource group. |
| Entra principal lookup | Supply `-FoundryUserObjectId` explicitly for a service principal, guest account, or pipeline. This avoids dependence on `az ad signed-in-user show`. No broad Entra directory role is required merely to assign Azure RBAC when a valid object ID and principal type are supplied. |
| Azure Policy | Customer policy must permit the resource types, private endpoints, managed identities, private DNS links, network injection, locations, tags, and SKUs used by the template. Policy exemptions must be approved before deployment when necessary. |
| Quota and availability | Customer confirms regional capacity/quota for the Foundry account and model, Cosmos DB, and Azure AI Search Standard. |

If the customer pre-registers providers, the deployment identity does not need subscription-level provider-registration access for Bicep itself. The supplied Chapter 01a wrapper nevertheless calls `az provider register`; in a tightly controlled customer subscription, use a customer-approved wrapper that verifies registration without attempting to register, or deploy the Bicep directly after the customer completes registration.

The supplied wrapper also contains tenant, subscription, and signed-in-user suffix checks. Before using it in a customer tenant, override its `-SubscriptionName`, `-Tenant`, and resource parameters. A guest identity or service principal may require adjusting the human-UPN suffix check in the wrapper.

#### Customer access request

The following text can be sent to the customer:

> Grant the deployment identity **Contributor** and **Role Based Access Control Administrator** on the target resource group. Pre-register `Microsoft.App`, `Microsoft.CognitiveServices`, `Microsoft.DocumentDB`, `Microsoft.KeyVault`, `Microsoft.Network`, `Microsoft.Search`, and `Microsoft.Storage` in the subscription. No subscription Owner or subscription Contributor access is required when the resource group already exists and providers are pre-registered. If VNets outside the target resource group will be linked, also grant read and VNet join access on those VNets. Provide the object ID and principal type of the user, group, or service principal that should receive Foundry User.

#### Customer deployment access summary

| Scope | Required access |
|---|---|
| Existing customer resource group | Contributor + Role Based Access Control Administrator (or User Access Administrator) |
| Subscription | No deployment role when the resource group exists and providers are pre-registered |
| Subscription, if the wrapper registers providers | Custom role containing `Microsoft.Resources/providers/register/action`, or a broader customer-approved role |
| External/shared VNet, when used | Reader plus VNet/subnet join permission, or Network Contributor |
| Entra ID | Target principal object ID supplied explicitly; no broad directory role normally required |
| Subscription Owner | Not required |

## 3. Stage-by-stage deployment inventory

## Stage 0 - Azure preparation

**Bicep:** None.

Prepare the subscription before running the chapter wrappers:

- Select the intended subscription and tenant.
- Create the target resource group, unless Chapter 01's wrapper will create it.
- Register the resource providers listed for each stage.
- Confirm regional availability and quota for Foundry models, Azure AI Search, Cosmos DB, and APIM.
- Assign the deployment identity Contributor and, where needed, Role Based Access Control Administrator on the target resource group.

A subscription administrator can register the union of providers once:

- `Microsoft.App`
- `Microsoft.ApiCenter`
- `Microsoft.ApiManagement`
- `Microsoft.Authorization`
- `Microsoft.CognitiveServices`
- `Microsoft.ContainerService`
- `Microsoft.DocumentDB`
- `Microsoft.Insights`
- `Microsoft.KeyVault`
- `Microsoft.ManagedIdentity`
- `Microsoft.Network`
- `Microsoft.OperationalInsights`
- `Microsoft.Search`
- `Microsoft.Storage`

---

## Stage 1 - Chapter 01: Foundry with bring-your-own networking

**Chapter:** [chapters/01-foundry-byo-networking.md](chapters/01-foundry-byo-networking.md)  
**Bicep:** [infra/chapter-01-foundry-byo-networking/main.bicep](infra/chapter-01-foundry-byo-networking/main.bicep)  
**Wrapper:** [infra/chapter-01-foundry-byo-networking/deploy.ps1](infra/chapter-01-foundry-byo-networking/deploy.ps1)  
**Deployment scope:** Resource group

### Infrastructure deployed by Bicep

- A new VNet when an existing VNet is not supplied.
- Foundry and private-endpoint subnets.
- Three Foundry private DNS zones and VNet links.
- Blob Storage and Key Vault private DNS zones and VNet links.
- Microsoft Foundry account and project with system-assigned identities.
- Optional model deployment when the template is called directly with `deployModel=true`.
- Storage account and Key Vault.
- Private endpoints and DNS zone groups for Foundry, Blob Storage, and Key Vault.
- Optional Foundry User role assignment for the supplied principal.

When the supplied wrapper is used, it passes `deployModel=false` to Bicep and creates the `gpt-4o` deployment afterward with Azure CLI to avoid an account-provisioning race.

### Existing resources referenced

If `ExistingVnetName` is supplied, the template references that VNet and its two existing subnets instead of creating them. If the VNet is in another resource group, the runner also needs read access to that resource group.

### Wrapper actions outside Bicep

- Creates or updates the resource group.
- Registers and waits for `Microsoft.App`, `Microsoft.CognitiveServices`, `Microsoft.ContainerService`, `Microsoft.KeyVault`, `Microsoft.Network`, and `Microsoft.Storage`.
- Resolves the Foundry User principal.
- Runs validation, what-if, and deployment.
- Optionally deploys `gpt-4o` with Azure CLI.

### Permissions

- **Subscription:** Resource Group Contributor or equivalent if the wrapper must create the resource group; provider-registration permission for the six providers above.
- **Resource group:** Contributor.
- **RBAC:** Role Based Access Control Administrator, User Access Administrator, or Owner because the template assigns Foundry User.
- **Directory:** The signed-in user can normally read its own object ID. Pass the object ID explicitly for automation.

---

## Stage 2 - Chapter 01a: Standard agent network injection

**Chapter coverage:** Extends Chapter 01 with the Standard Agent Setup dependencies.  
**Bicep:** [infra/chapter-01a-standard-agent-network-injection/main.bicep](infra/chapter-01a-standard-agent-network-injection/main.bicep)  
**Wrapper:** [infra/chapter-01a-standard-agent-network-injection/deploy.ps1](infra/chapter-01a-standard-agent-network-injection/deploy.ps1)  
**Deployment scope:** Resource group  
**Depends on:** Stage 1

### Infrastructure deployed by Bicep

- Standard Foundry account and project using network injection into the existing Foundry subnet.
- Storage account, Cosmos DB account, and Azure AI Search service.
- Cosmos DB and Search private DNS zones, VNet links, and optional links to additional VNets.
- Private endpoints and DNS zone groups for Foundry, Cosmos DB, Search, and Blob Storage.
- Foundry project connections to Storage, Cosmos DB, and Search.
- Account-level and project-level capability hosts.
- Azure RBAC assignments to the project identity:
  - Storage Blob Data Owner.
  - Cosmos DB Operator.
  - Search Index Data Contributor.
  - Search Service Contributor.
- Cosmos DB SQL Data Contributor assignment through a Cosmos SQL role assignment.
- Optional Foundry User assignment to a human or group.
- Optional model deployment when Bicep is called directly with `deployModel=true`.

The wrapper passes `deployModel=false` and creates `gpt-4o` afterward with Azure CLI.

### Existing resources referenced

- Chapter 01 VNet and both subnets.
- Chapter 01 Foundry private DNS zones.
- Chapter 01 Blob private DNS zone.

### Wrapper actions outside Bicep

- Validates that the Chapter 01 VNet exists.
- Registers and waits for `Microsoft.App`, `Microsoft.CognitiveServices`, `Microsoft.DocumentDB`, `Microsoft.KeyVault`, `Microsoft.Network`, `Microsoft.Search`, and `Microsoft.Storage`.
- Runs validation, what-if, and deployment.
- Optionally deploys `gpt-4o` with Azure CLI.

### Permissions

- **Subscription:** Provider-registration permission for the seven providers above, unless pre-registered.
- **Resource group:** Contributor.
- **Azure RBAC:** Role Based Access Control Administrator, User Access Administrator, or Owner for the four Azure role assignments and optional Foundry User assignment.
- **Cosmos SQL RBAC:** `Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments/write`, normally covered by Contributor at the resource-group scope.

---

## Stage 3 - Chapter 02: AI gateway

**Chapter:** [chapters/02-ai-gateway.md](chapters/02-ai-gateway.md)  
**Bicep:** [infra/chapter-02-ai-gateway/main.bicep](infra/chapter-02-ai-gateway/main.bicep)  
**Wrapper:** [infra/chapter-02-ai-gateway/deploy.ps1](infra/chapter-02-ai-gateway/deploy.ps1)  
**Deployment scope:** Resource group  
**Depends on:** Stage 1

### Infrastructure deployed by Bicep

- APIM network security group and required inbound/outbound rules.
- APIM subnet in the existing VNet.
- Internal Azure API Management instance using Developer or Premium v2 SKU.
- Application Insights component and APIM logger.
- `azure-api.net` private DNS zone and VNet link.
- Cognitive Services OpenAI User role assignment from the APIM managed identity to the existing Foundry account.

### Existing resources referenced

- Chapter 01 VNet.
- Existing Foundry account used as the APIM model backend.

### Wrapper actions outside Bicep

- Registers and waits for `Microsoft.ApiManagement`, `Microsoft.Insights`, and `Microsoft.OperationalInsights`.
- Runs validation, what-if, and deployment.
- Reads the APIM private IP and creates private DNS A records for gateway, developer portal, management, portal, and SCM hostnames.

### Permissions

- **Subscription:** Provider-registration permission for the three providers above, unless pre-registered.
- **Resource group:** Contributor, including DNS record creation after Bicep completes.
- **RBAC:** Role Based Access Control Administrator, User Access Administrator, or Owner for the APIM-to-Foundry role assignment.

---

## Stage 4A - Chapter 02a: MCP tools and A2A APIs

**Chapter:** [chapters/02a-mcp-a2a-samples.md](chapters/02a-mcp-a2a-samples.md)  
**Bicep:** [infra/chapter-02a-mcp-a2a/main.bicep](infra/chapter-02a-mcp-a2a/main.bicep)  
**Wrapper:** [infra/chapter-02a-mcp-a2a/deploy.ps1](infra/chapter-02a-mcp-a2a/deploy.ps1)  
**Deployment scope:** Resource group  
**Depends on:** Stage 3

### Infrastructure/configuration deployed by Bicep

- Published Agent Tools APIM product.
- Weather REST API, operation, policy, and product link.
- Weather MCP API, MCP tool binding, policy, and product link.
- Packing Advisor A2A backend API.
- Agent-card and send-message operations and policies.
- A2A backend product link.

### Existing resources referenced

- Chapter 02 APIM instance.

### Permissions

- **Resource group:** Contributor is the reliable baseline for the resource-group deployment.
- **RBAC:** No role-assignment permission is required; this template creates no role assignments.
- **Alternative:** API Management Service Contributor can manage APIM configuration, but a custom/combined role may still be required for the `Microsoft.Resources/deployments/*` operations used by `az deployment group`.

---

## Stage 4B - Chapter 04: API Center

**Chapter:** [chapters/04-api-center.md](chapters/04-api-center.md)  
**Bicep:** [infra/chapter-04-api-center/main.bicep](infra/chapter-04-api-center/main.bicep)  
**Wrapper:** [infra/chapter-04-api-center/deploy.ps1](infra/chapter-04-api-center/deploy.ps1)  
**Deployment scope:** Resource group  
**Depends on:** Stage 3

### Infrastructure deployed by Bicep

- User-assigned managed identity.
- Azure API Center service and APIM API source in the default workspace.
- Optional governance metadata schemas.
- Optional sample skill, agent, MCP, model, knowledge, and A2A catalog assets.
- API Management Service Reader assignment from the API Center identity to APIM.
- Optional Azure API Center Data Reader assignment to a human or group.

### Existing resources referenced

- Chapter 02 APIM instance.
- API Center's default workspace.

### Wrapper actions outside Bicep

- Requests registration of `Microsoft.ApiCenter`, `Microsoft.ManagedIdentity`, and `Microsoft.Authorization`.
- Runs validation, what-if, and deployment.
- Imports APIM APIs and MCP servers into API Center.
- Optionally creates an Entra application for managed portal sign-in.

### Permissions

- **Subscription:** Provider-registration permission for the three providers above, unless pre-registered.
- **Resource group:** Contributor.
- **RBAC:** Role Based Access Control Administrator, User Access Administrator, or Owner for both template role assignments.
- **Optional portal app:** Permission to create applications in the tenant and update the created application through Microsoft Graph. Tenant policy may require an Application Administrator or admin consent.

---

## Stage 5 - Chapter 06: Foundry IQ knowledge foundation

**Chapter:** [chapters/06-foundry-iq-knowledge.md](chapters/06-foundry-iq-knowledge.md)  
**Bicep:** [infra/chapter-06-foundry-iq/main.bicep](infra/chapter-06-foundry-iq/main.bicep)  
**Wrapper:** [infra/chapter-06-foundry-iq/deploy.ps1](infra/chapter-06-foundry-iq/deploy.ps1)  
**Deployment scope:** Resource group  
**Depends on:** Stage 2

### Infrastructure deployed by Bicep

- `text-embedding-3-small` deployment on the existing Standard Foundry account.
- Private knowledge-base blob container in the existing Standard Agent storage account.

### Existing resources referenced

- Chapter 01a Standard Foundry account.
- Chapter 01a storage account and Blob service.

### Permissions

- **Resource group:** Contributor is the reliable deployment baseline.
- **RBAC:** No role-assignment permission is required by this template.

### Data-plane permissions after Bicep

Bicep does not upload documents or create the Search index. The indexing scripts must run from a network location that can resolve and reach the private endpoints. Their identity needs appropriate data-plane roles, typically Storage Blob Data Contributor, Search Index Data Contributor, and permission to invoke the embedding model.

---

## Stage 6 - Chapter 15: Observability and guardrails

**Chapter:** [chapters/15-observability.md](chapters/15-observability.md)  
**Bicep:** [infra/chapter-15-observability/main.bicep](infra/chapter-15-observability/main.bicep)  
**Wrapper:** [infra/chapter-15-observability/deploy.ps1](infra/chapter-15-observability/deploy.ps1)  
**Deployment scope:** Resource group  
**Depends on:** Stages 2 and 3

### Infrastructure deployed by Bicep

- Log Analytics workspace.
- APIM diagnostic setting that sends gateway logs and metrics to Log Analytics.
- Azure Workbook for platform observability.
- Optional Responsible AI guardrail policy on the existing Foundry account.

### Existing resources referenced

- Chapter 02 APIM and Application Insights resources.
- Chapter 01a Standard Foundry account.

### Wrapper actions outside Bicep

- Optionally migrates Application Insights to the new workspace.
- Optionally applies the guardrail policy to an existing model deployment.

### Permissions

- **Resource group:** Contributor.
- **RBAC:** No role-assignment permission is required by this template.
- Contributor must cover updates to the existing APIM diagnostic settings, Foundry RAI policy, Application Insights component when migration is selected, and model deployment when guardrail application is selected.

---

## Stage 7 - Chapter 16: Defender for AI

**Chapter:** [chapters/16-defender.md](chapters/16-defender.md)  
**Bicep:** None.  
**Wrapper:** [infra/chapter-16-defender/deploy.ps1](infra/chapter-16-defender/deploy.ps1)  
**Depends on:** Stages 4A and 6

### Configuration performed outside Bicep

- Enables the subscription-level Defender for AI pricing plan.
- Enables AI prompt evidence and Purview sharing extensions.
- Optionally configures the Defender security contact.
- Uses Python for Foundry demo-agent creation and scenario execution.

### Permissions

- **Subscription:** Security Admin or a custom role containing `Microsoft.Security/pricings/read`, `Microsoft.Security/pricings/write`, and, when configuring contacts, `Microsoft.Security/securityContacts/read` and `Microsoft.Security/securityContacts/write`.
- **Resource group:** Reader for dependency checks; additional Foundry data-plane permissions are required to create and run the demo agent.
- **Network:** The execution host must reach the private Foundry and APIM endpoints.

---

## Stage 8 - Chapter 16a: End-to-end demonstration

**Runbook:** [infra/chapter-16a-end-to-end-demo/DEMO-SCRIPT.md](infra/chapter-16a-end-to-end-demo/DEMO-SCRIPT.md)  
**Bicep:** None.  
**Infrastructure deployed:** None.

This stage only demonstrates the resources created in earlier stages. The presenter needs portal and data-plane read/use access to Foundry, APIM, API Center, Application Insights, Log Analytics, Workbooks, and Defender for Cloud.

## 4. Quick reference

| Stage | Chapter | Bicep | Main components | Required deployment roles |
|---|---|---|---|---|
| 0 | Preparation | None | Resource group, provider registration, quota | Subscription preparation role |
| 1 | 01 | `infra/chapter-01-foundry-byo-networking/main.bicep` | VNet, private DNS/endpoints, Foundry, Storage, Key Vault | Contributor + RBAC Administrator; subscription rights for RG/provider setup |
| 2 | 01a | `infra/chapter-01a-standard-agent-network-injection/main.bicep` | Standard Foundry, Cosmos, Search, Storage, connections, capability hosts | Contributor + RBAC Administrator |
| 3 | 02 | `infra/chapter-02-ai-gateway/main.bicep` | APIM, NSG/subnet, App Insights, DNS | Contributor + RBAC Administrator |
| 4A | 02a | `infra/chapter-02a-mcp-a2a/main.bicep` | APIM product, REST/MCP/A2A APIs and policies | Contributor |
| 4B | 04 | `infra/chapter-04-api-center/main.bicep` | API Center, identity, metadata, catalog assets | Contributor + RBAC Administrator |
| 5 | 06 | `infra/chapter-06-foundry-iq/main.bicep` | Embedding deployment, blob container | Contributor |
| 6 | 15 | `infra/chapter-15-observability/main.bicep` | Log Analytics, diagnostics, workbook, RAI policy | Contributor |
| 7 | 16 | None | Defender for AI and demo agent | Security Admin at subscription + data-plane access |
| 8 | 16a | None | Demo orchestration only | Read/use access to demonstrated services |

## 5. Chapters without deployable Bicep

No `main.bicep` currently exists under `infra/` for Chapters 00, 03, 05, 07-14, 16-30, except for the non-Bicep Chapter 16 and 16a assets described above. Those chapters document architecture, governance, application development, or future/production patterns; they should not be treated as automated infrastructure stages until templates are added.

## 6. Important operational cautions

- Always run each wrapper without `-Execute` first to validate and review the what-if result.
- APIM creation can take 30-45 minutes.
- Model deployment is intentionally outside Bicep in the Chapter 01 and 01a wrappers.
- Private data-plane operations must run from the VNet, a peered network, or another host with private DNS resolution and routing.
- Role assignment propagation can delay capability-host or connection readiness.
- Built-in service-specific roles may manage a service but still omit `Microsoft.Resources/deployments/*`; Contributor is therefore the documented baseline for running these resource-group Bicep deployments.
- Use custom roles and RBAC assignment conditions for production least privilege rather than granting broad subscription Owner access.
