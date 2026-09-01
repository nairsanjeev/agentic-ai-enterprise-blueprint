// STEP 00B — LAB ONLY: simulate the centrally managed private DNS zones Zava provides.
//
// Do NOT run this in the real customer environment. In production, obtain the existing
// zone resource group from Zava's DNS team and start with Step 02.

targetScope = 'resourceGroup'

var zoneNames = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
  'privatelink.blob.${az.environment().suffixes.storage}'
  'privatelink.vaultcore.azure.net'
  'privatelink.documents.azure.com'
  'privatelink.search.windows.net'
]

resource zones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for zoneName in zoneNames: {
  name: zoneName
  location: 'global'
  tags: {
    customer: 'Zava'
    purpose: 'customer-dns-simulation'
    managedBy: 'Bicep'
  }
}]

output zoneResourceIds array = [for (zoneName, index) in zoneNames: {
  name: zoneName
  id: zones[index].id
}]
output warning string = 'LAB ONLY. Real Zava private DNS zones are customer-owned existing resources.'
