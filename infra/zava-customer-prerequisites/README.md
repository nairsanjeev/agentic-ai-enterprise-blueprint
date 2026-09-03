# Zava customer prerequisite simulation

This template simulates the resources Zava's networking and platform teams would provide before Chapters 01 and 01a are deployed.

## Target

- Subscription: `ME-MngEnvMCAP152025-snair-1`
- Resource group: `rg-jnj-agentic-blueprint`
- Region: `eastus`

## Resources

- VNet: `zava-dev-vnet` (`10.240.0.0/16`)
- Foundry agent subnet: `snet-foundry` (`10.240.0.0/24`), delegated to `Microsoft.App/environments`
- Private endpoint subnet: `snet-privateendpoints` (`10.240.1.0/24`), private endpoint policies disabled
- Seven private DNS zones required by Chapters 01 and 01a
- One VNet link from each private DNS zone to `zava-dev-vnet`

This template does not deploy Foundry, Storage, Key Vault, Cosmos DB, Azure AI Search, models, private endpoints, route tables, firewalls, NAT gateways, or application resources.

## Deploy

```powershell
az account set --subscription 'ME-MngEnvMCAP152025-snair-1'

az deployment group what-if `
  --resource-group 'rg-jnj-agentic-blueprint' `
  --name 'zava-customer-prerequisites' `
  --template-file .\infra\zava-customer-prerequisites\main.bicep `
  --parameters location='eastus'

az deployment group create `
  --resource-group 'rg-jnj-agentic-blueprint' `
  --name 'zava-customer-prerequisites' `
  --template-file .\infra\zava-customer-prerequisites\main.bicep `
  --parameters location='eastus'
```

## Chapter deployment values

Use these values when testing the chapter deployments:

```powershell
$workloadRg  = 'rg-jnj-agentic-blueprint'
$networkRg   = 'rg-jnj-agentic-blueprint'
$location    = 'eastus'
$vnet        = 'zava-dev-vnet'
$agentSubnet = 'snet-foundry'
$peSubnet    = 'snet-privateendpoints'
$workload    = 'zava'
$environment = 'dev'
```

Chapter 01 can consume this VNet with its existing BYO-network parameters. Chapter 01a currently supports a VNet in the deployment resource group, which matches this simulation.
