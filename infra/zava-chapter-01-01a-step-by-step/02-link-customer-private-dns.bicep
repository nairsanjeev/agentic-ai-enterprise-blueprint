// STEP 02 — LAB/CUSTOMER PLATFORM STEP: link Zava-owned private DNS zones to the VNet.
//
// The workload deployment does not create private DNS zones. It references zones that
// Zava owns. Run this step only when the zones already exist and Zava authorizes this
// deployment identity to create VNet links. In production, Zava's DNS team may perform
// the equivalent operation through its central DNS automation.

targetScope = 'resourceGroup'

@description('Resource group containing the customer-owned VNet.')
param networkResourceGroupName string

param vnetName string = 'azr-133-eastus'

var zoneNames = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
  'privatelink.blob.${az.environment().suffixes.storage}'
  'privatelink.vaultcore.azure.net'
  'privatelink.documents.azure.com'
  'privatelink.search.windows.net'
]

resource customerVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
  scope: resourceGroup(networkResourceGroupName)
}

// Deploy this file to the private DNS resource group. The zones are local existing
// resources; only the VNet reference crosses resource-group scope.
resource customerZones 'Microsoft.Network/privateDnsZones@2024-06-01' existing = [for zoneName in zoneNames: {
  name: zoneName
}]

// registrationEnabled is false because these zones hold records registered by private
// endpoint DNS zone groups; ordinary VM host registration is not required.
resource links 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (zoneName, index) in zoneNames: {
  parent: customerZones[index]
  name: 'link-${vnetName}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: customerVnet.id
    }
  }
}]

output linkedZones array = zoneNames
output vnetResourceId string = customerVnet.id
