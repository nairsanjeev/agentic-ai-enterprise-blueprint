// STEP 03 — Chapter 01 private Foundry foundation.
//
// Creates the original/private Foundry account, project, Storage, Key Vault, and their
// private endpoints. It does NOT create or modify the customer VNet, subnets, DNS zones,
// DNS VNet links, route tables, NSGs, or firewalls.
//
// Chapter 01 is retained for parity with the framework. Production hosted agents that
// need VNet-routed egress should be built on the Standard account created in Steps 04–06.

targetScope = 'resourceGroup'

param location string = resourceGroup().location
param workloadName string = 'zava'
param environment string = 'dev'
param networkResourceGroupName string
param vnetName string = 'azr-133-eastus'
param privateEndpointSubnetName string = 'snet-zava-privateendpoints'
param privateDnsResourceGroupName string
@description('Create private endpoint DNS-zone groups against Zava-owned zones. Set false when Zava DNS automation owns record registration.')
param createPrivateEndpointDnsZoneGroups bool = true
param foundryUserPrincipalId string = ''

var prefix = '${toLower(workloadName)}-${environment}'
var suffix = take(uniqueString(subscription().subscriptionId, resourceGroup().id, 'zava-basic'), 8)
var foundryAccountName = take('${prefix}-foundry-${suffix}', 64)
var foundryProjectName = take('${prefix}-project', 64)
var storageAccountName = take('st${uniqueString(subscription().subscriptionId, resourceGroup().id, 'zava-basic')}', 24)
var keyVaultName = take('${prefix}-kv-${suffix}', 24)

var roleFoundryUser = '53ca6127-db72-4b80-b1b0-d745d6d5456d'
var commonTags = {
  customer: 'Zava'
  workload: workloadName
  environment: environment
  chapter: '01'
  managedBy: 'Bicep'
}

// Customer-owned network references. No network resource is created in this template.
resource customerVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
  scope: resourceGroup(networkResourceGroupName)
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: customerVnet
  name: privateEndpointSubnetName
}

// Customer-owned private DNS zone references. Their VNet links were established in Step 02.
resource cognitiveDns 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.cognitiveservices.azure.com'
  scope: resourceGroup(privateDnsResourceGroupName)
}
resource openAiDns 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.openai.azure.com'
  scope: resourceGroup(privateDnsResourceGroupName)
}
resource servicesAiDns 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.services.ai.azure.com'
  scope: resourceGroup(privateDnsResourceGroupName)
}
resource blobDns 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.blob.${az.environment().suffixes.storage}'
  scope: resourceGroup(privateDnsResourceGroupName)
}
resource vaultDns 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.vaultcore.azure.net'
  scope: resourceGroup(privateDnsResourceGroupName)
}

// Basic/private Foundry account. Public data-plane access and API-key authentication are disabled.
resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: foundryAccountName
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  tags: commonTags
  properties: {
    allowProjectManagement: true
    customSubDomainName: foundryAccountName
    disableLocalAuth: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: foundryAccount
  name: foundryProjectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  tags: commonTags
  properties: {
    displayName: 'Zava ${environment} foundation'
    description: 'Chapter 01 private foundation; use the Standard project for network-injected agents.'
  }
}

// Private supporting resources. Shared/local keys and public data-plane access are disabled.
resource storage 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  tags: commonTags
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Disabled'
    supportsHttpsTrafficOnly: true
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: keyVaultName
  location: location
  tags: commonTags
  properties: {
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    publicNetworkAccess: 'Disabled'
    sku: {
      family: 'A'
      name: 'standard'
    }
  }
}

// Three private endpoints consume three addresses in the /28 PE subnet.
resource foundryPe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${foundryAccount.name}'
  location: location
  tags: commonTags
  properties: {
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'foundry-account'
        properties: {
          privateLinkServiceId: foundryAccount.id
          groupIds: [
            'account'
          ]
        }
      }
    ]
  }
}

resource foundryPeDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (createPrivateEndpointDnsZoneGroups) {
  parent: foundryPe
  name: 'customer-dns'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'cognitive', properties: { privateDnsZoneId: cognitiveDns.id } }
      { name: 'openai', properties: { privateDnsZoneId: openAiDns.id } }
      { name: 'services-ai', properties: { privateDnsZoneId: servicesAiDns.id } }
    ]
  }
}

resource storagePe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${storage.name}-blob'
  location: location
  tags: commonTags
  properties: {
    subnet: { id: privateEndpointSubnet.id }
    privateLinkServiceConnections: [
      {
        name: 'storage-blob'
        properties: {
          privateLinkServiceId: storage.id
          groupIds: [ 'blob' ]
        }
      }
    ]
  }
}
resource storagePeDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (createPrivateEndpointDnsZoneGroups) {
  parent: storagePe
  name: 'customer-dns'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'blob', properties: { privateDnsZoneId: blobDns.id } }
    ]
  }
}

resource vaultPe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${keyVault.name}'
  location: location
  tags: commonTags
  properties: {
    subnet: { id: privateEndpointSubnet.id }
    privateLinkServiceConnections: [
      {
        name: 'key-vault'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [ 'vault' ]
        }
      }
    ]
  }
}
resource vaultPeDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (createPrivateEndpointDnsZoneGroups) {
  parent: vaultPe
  name: 'customer-dns'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'vault', properties: { privateDnsZoneId: vaultDns.id } }
    ]
  }
}

// Optional human access. Role assignment creation requires RBAC Administrator or equivalent.
resource foundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(foundryUserPrincipalId)) {
  scope: foundryProject
  name: guid(foundryProject.id, foundryUserPrincipalId, roleFoundryUser)
  properties: {
    principalId: foundryUserPrincipalId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleFoundryUser)
  }
}

output foundryAccountName string = foundryAccount.name
output foundryProjectName string = foundryProject.name
output storageAccountName string = storage.name
output keyVaultName string = keyVault.name
output privateEndpoints array = [ foundryPe.name, storagePe.name, vaultPe.name ]
