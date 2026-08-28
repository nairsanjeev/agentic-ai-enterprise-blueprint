@description('Azure region for every Chapter 01 resource. The Foundry account and VNet must be in the same region.')
param location string = resourceGroup().location

@description('Short workload name used in human-readable resource names.')
@minLength(2)
@maxLength(20)
param workloadName string = 'agent-blueprint'

@description('Deployment environment name used in tags and resource names.')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Address range for the platform VNet. The 192.168 range is accepted in every Foundry Agent Service region.')
param vnetAddressPrefix string = '192.168.0.0/16'

@description('Dedicated subnet delegated to Microsoft.App/environments for Foundry Agent Service network injection.')
param foundrySubnetPrefix string = '192.168.0.0/24'

@description('Subnet used only by private endpoints for Foundry and its supporting resources.')
param privateEndpointSubnetPrefix string = '192.168.1.0/24'

@description('Name of an existing VNet to deploy into (bring-your-own network). Leave empty to create a new VNet from the address prefixes above.')
param existingVnetName string = ''

@description('Resource group of the existing VNet when it is not in this deployment resource group. Leave empty to use this resource group.')
param existingVnetResourceGroupName string = ''

@description('Name of the delegated Foundry agent subnet in the new or existing VNet.')
param foundrySubnetName string = 'snet-foundry'

@description('Name of the private endpoint subnet in the new or existing VNet.')
param privateEndpointSubnetName string = 'snet-privateendpoints'

@description('Deploy the gpt-4o model from the chapter. Set false if the region has no quota or the model version is unavailable.')
param deployModel bool = true

@description('Model deployment name exposed by the Foundry account.')
param modelDeploymentName string = 'gpt-4o'

@description('Azure OpenAI model version requested by Chapter 01.')
param modelVersion string = '2024-11-20'

@description('GlobalStandard model capacity in thousands of tokens per minute. Deployment requires available regional quota.')
@minValue(1)
param modelCapacity int = 30

@description('Object ID (principal) granted the Foundry User role so it can build agents in the project. Empty skips the assignment.')
param foundryUserPrincipalId string = ''

@description('Principal type for the Foundry User role assignment.')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param foundryUserPrincipalType string = 'User'

var normalizedWorkloadName = toLower(replace(workloadName, '_', '-'))
var namePrefix = '${normalizedWorkloadName}-${environment}'
var uniqueSuffix = take(uniqueString(subscription().subscriptionId, resourceGroup().id), 8)
var foundryAccountName = take('${namePrefix}-foundry-${uniqueSuffix}', 64)
var foundryProjectName = take('${namePrefix}-project', 64)
var storageAccountName = 'st${uniqueString(subscription().subscriptionId, resourceGroup().id, workloadName, environment)}'
var keyVaultName = take('${namePrefix}-kv-${uniqueSuffix}', 24)

var commonTags = {
  workload: workloadName
  environment: environment
  chapter: '01-foundry-byo-networking'
  managedBy: 'Bicep'
}

// When existingVnetName is provided the module reuses the customer's network and
// subnets; otherwise it creates a new VNet from the address prefixes above.
var createNetwork = empty(existingVnetName)
var networkResourceGroupName = !empty(existingVnetResourceGroupName) ? existingVnetResourceGroupName : resourceGroup().name
var vnetName = createNetwork ? '${namePrefix}-vnet' : existingVnetName

// Two subnets are intentionally separated: delegated Foundry compute cannot share
// a subnet with private endpoints. A /24 leaves upgrade and scaling headroom.
// Created only when no existing VNet is supplied.
resource newVirtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = if (createNetwork) {
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
        name: foundrySubnetName
        properties: {
          addressPrefix: foundrySubnetPrefix
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

// Unified reference to the new or customer-provided VNet and its subnets.
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
  scope: resourceGroup(networkResourceGroupName)
}

resource foundrySubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: virtualNetwork
  name: foundrySubnetName
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: virtualNetwork
  name: privateEndpointSubnetName
}

// Foundry currently uses three private DNS suffixes across its AI Services,
// Azure OpenAI, and project endpoints. All three point at the same private endpoint.
var foundryDnsZoneNames = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
]

resource foundryDnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for zoneName in foundryDnsZoneNames: {
  name: zoneName
  location: 'global'
  tags: commonTags
}]

resource foundryDnsLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (zoneName, index) in foundryDnsZoneNames: {
  parent: foundryDnsZones[index]
  name: 'link-${namePrefix}-vnet'
  location: 'global'
  tags: commonTags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
  dependsOn: [
    newVirtualNetwork
  ]
}]

resource blobDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.blob.${az.environment().suffixes.storage}'
  location: 'global'
  tags: commonTags
}

resource blobDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: blobDnsZone
  name: 'link-${namePrefix}-vnet'
  location: 'global'
  tags: commonTags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
  dependsOn: [
    newVirtualNetwork
  ]
}

resource keyVaultDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  tags: commonTags
}

resource keyVaultDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: keyVaultDnsZone
  name: 'link-${namePrefix}-vnet'
  location: 'global'
  tags: commonTags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
  dependsOn: [
    newVirtualNetwork
  ]
}

// This is the Microsoft Foundry account (an AIServices Cognitive Services account).
// Public data-plane access and API keys are disabled to enforce private, Entra-based access.
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

// The chapter labels model deployment as project creation. This child resource
// creates the actual Foundry project before the optional model is deployed.
resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: foundryAccount
  name: foundryProjectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  tags: commonTags
  properties: {
    displayName: '${workloadName} ${environment}'
    description: 'Chapter 01 private networking project'
  }
}

resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = if (deployModel) {
  parent: foundryAccount
  name: modelDeploymentName
  sku: {
    name: 'GlobalStandard'
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: modelVersion
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
}

// Storage is private by default and uses Microsoft Entra authorization instead
// of shared keys. The blob private endpoint implements the chapter's storage scope.
resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
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

resource foundryPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${foundryAccountName}'
  location: location
  tags: commonTags
  properties: {
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'foundry-account-connection'
        properties: {
          privateLinkServiceId: foundryAccount.id
          groupIds: [
            'account'
          ]
        }
      }
    ]
  }
  dependsOn: [
    newVirtualNetwork
  ]
}

resource foundryDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: foundryPrivateEndpoint
  name: 'foundry-dns-group'
  properties: {
    privateDnsZoneConfigs: [for (zoneName, index) in foundryDnsZoneNames: {
      name: replace(zoneName, '.', '-')
      properties: {
        privateDnsZoneId: foundryDnsZones[index].id
      }
    }]
  }
}

resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${storageAccount.name}-blob'
  location: location
  tags: commonTags
  properties: {
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'storage-blob-connection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
  dependsOn: [
    newVirtualNetwork
  ]
}

resource storageDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: storagePrivateEndpoint
  name: 'storage-dns-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob'
        properties: {
          privateDnsZoneId: blobDnsZone.id
        }
      }
    ]
  }
}

resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${keyVault.name}'
  location: location
  tags: commonTags
  properties: {
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'key-vault-connection'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
  dependsOn: [
    newVirtualNetwork
  ]
}

resource keyVaultDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: keyVaultPrivateEndpoint
  name: 'key-vault-dns-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'vault'
        properties: {
          privateDnsZoneId: keyVaultDnsZone.id
        }
      }
    ]
  }
}

// Built-in Foundry User (formerly Azure AI User) role — grants data-plane access to build agents.
var foundryUserRoleId = '53ca6127-db72-4b80-b1b0-d745d6d5456d'

resource foundryUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(foundryUserPrincipalId)) {
  scope: foundryProject
  name: guid(foundryProject.id, foundryUserPrincipalId, foundryUserRoleId)
  properties: {
    principalId: foundryUserPrincipalId
    principalType: foundryUserPrincipalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', foundryUserRoleId)
  }
}

output foundryAccountName string = foundryAccount.name
output foundryProjectName string = foundryProject.name
output foundryProjectResourceId string = foundryProject.id
output foundryEndpoint string = foundryAccount.properties.endpoint
output storageAccountName string = storageAccount.name
output keyVaultName string = keyVault.name
output vnetName string = vnetName
output vnetResourceGroupName string = networkResourceGroupName
output createdNetwork bool = createNetwork
output virtualNetworkName string = virtualNetwork.name
output foundrySubnetId string = foundrySubnet.id
output privateEndpointSubnetId string = privateEndpointSubnet.id
output portalConfigurationRequired string = 'Configure Foundry Agent Service virtual network injection with the emitted foundrySubnetId before creating agents.'