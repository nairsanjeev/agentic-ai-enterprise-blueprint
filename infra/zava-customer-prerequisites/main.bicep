// Simulated customer-owned prerequisites for testing the Zava deployment runbook.
// This template creates only the resources that Zava's networking/platform teams
// would provide before Chapters 01 and 01a are deployed.

targetScope = 'resourceGroup'

@description('Azure region for the customer-owned VNet. Foundry must use the same region.')
param location string = resourceGroup().location

@description('Name of the simulated customer-owned VNet.')
param vnetName string = 'zava-dev-vnet'

@description('Address space for the simulated customer-owned VNet.')
param vnetAddressPrefix string = '10.240.0.0/16'

@description('Name of the subnet delegated for Foundry Agent Service network injection.')
param agentSubnetName string = 'snet-foundry'

@description('Address prefix for the delegated Foundry agent subnet.')
param agentSubnetPrefix string = '10.240.0.0/24'

@description('Name of the subnet dedicated to private endpoints.')
param privateEndpointSubnetName string = 'snet-privateendpoints'

@description('Address prefix for the private endpoint subnet.')
param privateEndpointSubnetPrefix string = '10.240.1.0/24'

var commonTags = {
  workload: 'zava-agentic-blueprint'
  environment: 'dev'
  purpose: 'customer-network-simulation'
  ownership: 'zava-platform-team'
  managedBy: 'Bicep'
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: commonTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
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
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

var privateDnsZoneNames = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
  'privatelink.blob.${az.environment().suffixes.storage}'
  'privatelink.vaultcore.azure.net'
  'privatelink.documents.azure.com'
  'privatelink.search.windows.net'
]

resource privateDnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for zoneName in privateDnsZoneNames: {
  name: zoneName
  location: 'global'
  tags: commonTags
}]

resource privateDnsVnetLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (zoneName, index) in privateDnsZoneNames: {
  parent: privateDnsZones[index]
  name: 'link-${vnetName}'
  location: 'global'
  tags: commonTags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}]

output vnetName string = virtualNetwork.name
output vnetResourceId string = virtualNetwork.id
output agentSubnetName string = agentSubnetName
output agentSubnetResourceId string = virtualNetwork.properties.subnets[0].id
output privateEndpointSubnetName string = privateEndpointSubnetName
output privateEndpointSubnetResourceId string = virtualNetwork.properties.subnets[1].id
output privateDnsZoneResourceIds array = [for (zoneName, index) in privateDnsZoneNames: {
  name: zoneName
  id: privateDnsZones[index].id
}]
