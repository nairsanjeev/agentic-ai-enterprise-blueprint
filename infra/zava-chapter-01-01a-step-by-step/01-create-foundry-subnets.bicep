// STEP 01 — Create the two workload subnets inside Zava's existing VNet.
//
// Microsoft Foundry Standard Agent private networking needs TWO separate subnets:
// 1. A dedicated delegated subnet for injected agent compute.
// 2. A private endpoint subnet for Foundry and customer-owned data services.
//
// A /27 is the minimum supported delegated agent subnet. Microsoft recommends /24,
// but Zava's entire supplied VNet is /25. This design uses /27 (32 total addresses)
// and therefore supports the deployment but has less scale headroom than recommended.
// The agent subnet is exclusive to one Foundry Standard account.
//
// The /28 private endpoint subnet has 11 Azure-usable addresses. Chapters 01 and 01a
// use seven private endpoints, leaving limited room. Do not add unrelated endpoints.

targetScope = 'resourceGroup'

@description('Name of the customer-owned VNet.')
param vnetName string = 'azr-133-eastus'

@description('Dedicated private endpoint subnet name.')
param privateEndpointSubnetName string = 'snet-zava-privateendpoints'

@description('Approved CIDR for the private endpoint subnet. Must fit in the customer VNet without overlap.')
param privateEndpointSubnetPrefix string = '10.75.139.144/28'

@description('Dedicated Foundry agent runtime subnet name.')
param agentSubnetName string = 'snet-zava-foundry-agent'

@description('Approved CIDR for the exclusive Foundry agent subnet. Microsoft requires /27 or larger and recommends /24.')
param agentSubnetPrefix string = '10.75.139.160/27'

// Deploy this template to the VNet's resource group. This keeps subnet writes inside
// the customer network scope and avoids cross-resource-group child-resource deployment.
resource customerVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
}

// This block adds only the private endpoint child subnet. Existing customer subnets are
// not represented here and are not replaced. Network policy is disabled because Azure
// Private Link endpoints are placed in this subnet.
resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: customerVnet
  name: privateEndpointSubnetName
  properties: {
    addressPrefix: privateEndpointSubnetPrefix
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

// This subnet is dedicated to one Standard Foundry account. The delegation allows the
// Foundry Agent Service/Container Apps infrastructure to inject agent runtime compute.
resource agentSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: customerVnet
  name: agentSubnetName
  properties: {
    addressPrefix: agentSubnetPrefix
    delegations: [
      {
        name: 'foundry-agent-service-delegation'
        properties: {
          serviceName: 'Microsoft.App/environments'
        }
      }
    ]
  }
}

output privateEndpointSubnetId string = privateEndpointSubnet.id
output privateEndpointSubnetPrefix string = privateEndpointSubnetPrefix
output agentSubnetId string = agentSubnet.id
output agentSubnetPrefix string = agentSubnetPrefix
output remainingUnallocatedRange string = '10.75.139.192/26'
