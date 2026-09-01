// STEP 04 — Chapter 01a Standard Agent core and customer-owned state.
//
// Creates:
// - Standard Foundry account with network injection configured at account creation.
// - Standard Foundry project with a system-assigned managed identity.
// - Private Storage, Cosmos DB, and Azure AI Search resources.
// - Four private endpoints and customer private DNS zone-group associations.
// - Entra/RBAC roles and three AAD project connections.
//
// This step intentionally does NOT create capability hosts. Separating those one-time,
// non-idempotent resources into Step 05 makes failures easier to diagnose and recover.

targetScope = 'resourceGroup'

param location string = resourceGroup().location
param searchLocation string = location
param workloadName string = 'zava'
param environment string = 'dev'
param networkResourceGroupName string
param vnetName string = 'azr-133-eastus'
param agentSubnetName string = 'snet-zava-foundry-agent'
param privateEndpointSubnetName string = 'snet-zava-privateendpoints'
param privateDnsResourceGroupName string
@description('Create private endpoint DNS-zone groups against Zava-owned zones. Set false when Zava DNS automation owns record registration.')
param createPrivateEndpointDnsZoneGroups bool = true
param foundryUserPrincipalId string = ''

var prefix = '${toLower(workloadName)}-${environment}'
var suffix = take(uniqueString(subscription().subscriptionId, resourceGroup().id, 'zava-standard'), 8)
var foundryAccountName = take('${prefix}-foundry-std-${suffix}', 63)
var foundryProjectName = take('${prefix}-project-std', 63)
var storageName = take('ststd${uniqueString(subscription().subscriptionId, resourceGroup().id, 'zava-standard')}', 24)
var cosmosName = take('${prefix}-cosmos-${suffix}', 44)
var searchName = take('${prefix}-search-${suffix}', 60)

var storageConnectionName = 'agent-storage'
var cosmosConnectionName = 'agent-thread-storage'
var searchConnectionName = 'agent-vector-store'

var roleFoundryUser = '53ca6127-db72-4b80-b1b0-d745d6d5456d'
var roleStorageBlobDataOwner = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var roleCosmosDbOperator = '230815da-be43-4aae-9cb4-875f7bd000aa'
var roleSearchIndexDataContributor = '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
var roleSearchServiceContributor = '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
var cosmosDataContributorRoleGuid = '00000000-0000-0000-0000-000000000002'

var commonTags = {
  customer: 'Zava'
  workload: workloadName
  environment: environment
  chapter: '01a'
  managedBy: 'Bicep'
}

// Existing Zava network. Foundry must be in the same Azure region as this VNet.
resource customerVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
  scope: resourceGroup(networkResourceGroupName)
}
resource agentSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: customerVnet
  name: agentSubnetName
}
resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: customerVnet
  name: privateEndpointSubnetName
}

// Existing Zava-owned DNS zones. The workload creates only PE zone groups/records.
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
resource cosmosDns 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.documents.azure.com'
  scope: resourceGroup(privateDnsResourceGroupName)
}
resource searchDns 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.search.windows.net'
  scope: resourceGroup(privateDnsResourceGroupName)
}

// Agent file storage. Entra-only and private-only.
resource storage 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageName
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  tags: commonTags
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Disabled'
    supportsHttpsTrafficOnly: true
  }
}

// Agent thread/message store. Local keys and public network access are disabled.
resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = {
  name: cosmosName
  location: location
  kind: 'GlobalDocumentDB'
  tags: commonTags
  properties: {
    databaseAccountOfferType: 'Standard'
    disableLocalAuth: true
    enableAutomaticFailover: false
    publicNetworkAccess: 'Disabled'
    consistencyPolicy: { defaultConsistencyLevel: 'Session' }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
  }
}

// Agent vector store. Standard tier is required; semantic ranker supports later IQ use.
resource search 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: searchName
  location: searchLocation
  identity: { type: 'SystemAssigned' }
  sku: { name: 'standard' }
  tags: commonTags
  properties: {
    authOptions: null
    disableLocalAuth: true
    hostingMode: 'default'
    partitionCount: 1
    publicNetworkAccess: 'disabled'
    replicaCount: 1
    semanticSearch: 'free'
  }
}

// Network injection is immutable after hosted agents exist, so it is configured when the
// Standard account is first created. The /27 subnet is dedicated to this account.
resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: foundryAccountName
  location: location
  kind: 'AIServices'
  sku: { name: 'S0' }
  identity: { type: 'SystemAssigned' }
  tags: commonTags
  properties: {
    allowProjectManagement: true
    customSubDomainName: foundryAccountName
    disableLocalAuth: true
    publicNetworkAccess: 'Disabled'
    networkInjections: [
      {
        scenario: 'agent'
        subnetArmId: agentSubnet.id
        useMicrosoftManagedNetwork: false
      }
    ]
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
  identity: { type: 'SystemAssigned' }
  tags: commonTags
  properties: {
    displayName: 'Zava ${environment} Standard Agent'
    description: 'Network-injected Standard Agent project with customer-owned state.'
  }
}

// Four more endpoints fill seven of the /28 subnet's eleven Azure-usable addresses.
resource foundryPe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${foundryAccount.name}'
  location: location
  tags: commonTags
  properties: {
    subnet: { id: privateEndpointSubnet.id }
    privateLinkServiceConnections: [
      {
        name: 'foundry-standard'
        properties: {
          privateLinkServiceId: foundryAccount.id
          groupIds: [ 'account' ]
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
      { name: 'storage-blob', properties: { privateLinkServiceId: storage.id, groupIds: [ 'blob' ] } }
    ]
  }
}
resource storagePeDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (createPrivateEndpointDnsZoneGroups) {
  parent: storagePe
  name: 'customer-dns'
  properties: { privateDnsZoneConfigs: [ { name: 'blob', properties: { privateDnsZoneId: blobDns.id } } ] }
}

resource cosmosPe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${cosmos.name}'
  location: location
  tags: commonTags
  properties: {
    subnet: { id: privateEndpointSubnet.id }
    privateLinkServiceConnections: [
      { name: 'cosmos-sql', properties: { privateLinkServiceId: cosmos.id, groupIds: [ 'Sql' ] } }
    ]
  }
}
resource cosmosPeDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (createPrivateEndpointDnsZoneGroups) {
  parent: cosmosPe
  name: 'customer-dns'
  properties: { privateDnsZoneConfigs: [ { name: 'cosmos', properties: { privateDnsZoneId: cosmosDns.id } } ] }
}

resource searchPe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${search.name}'
  location: location
  tags: commonTags
  properties: {
    subnet: { id: privateEndpointSubnet.id }
    privateLinkServiceConnections: [
      { name: 'search', properties: { privateLinkServiceId: search.id, groupIds: [ 'searchService' ] } }
    ]
  }
}
resource searchPeDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (createPrivateEndpointDnsZoneGroups) {
  parent: searchPe
  name: 'customer-dns'
  properties: { privateDnsZoneConfigs: [ { name: 'search', properties: { privateDnsZoneId: searchDns.id } } ] }
}

// The project managed identity receives only the roles required to provision/use state.
var projectPrincipalId = foundryProject.identity.principalId
resource storageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(storage.id, foundryProject.id, roleStorageBlobDataOwner)
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleStorageBlobDataOwner)
  }
}
resource cosmosOperatorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: cosmos
  name: guid(cosmos.id, foundryProject.id, roleCosmosDbOperator)
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleCosmosDbOperator)
  }
}
resource cosmosDataRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-11-15' = {
  parent: cosmos
  name: guid(cosmos.id, foundryProject.id, cosmosDataContributorRoleGuid)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: '${cosmos.id}/sqlRoleDefinitions/${cosmosDataContributorRoleGuid}'
    scope: cosmos.id
  }
}
resource searchIndexRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: search
  name: guid(search.id, foundryProject.id, roleSearchIndexDataContributor)
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleSearchIndexDataContributor)
  }
}
resource searchServiceRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: search
  name: guid(search.id, foundryProject.id, roleSearchServiceContributor)
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleSearchServiceContributor)
  }
}
resource foundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(foundryUserPrincipalId)) {
  scope: foundryProject
  name: guid(foundryProject.id, foundryUserPrincipalId, roleFoundryUser)
  properties: {
    principalId: foundryUserPrincipalId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleFoundryUser)
  }
}

// AAD project connections identify each customer-owned dependency for Step 05.
resource storageConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: foundryProject
  name: storageConnectionName
  properties: {
    category: 'AzureStorageAccount'
    target: storage.properties.primaryEndpoints.blob
    authType: 'AAD'
    isSharedToAll: true
    metadata: { ApiType: 'Azure', ResourceId: storage.id, location: location }
  }
}
resource cosmosConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: foundryProject
  name: cosmosConnectionName
  properties: {
    category: 'CosmosDB'
    target: cosmos.properties.documentEndpoint
    authType: 'AAD'
    isSharedToAll: true
    metadata: { ApiType: 'Azure', ResourceId: cosmos.id, location: location }
  }
}
resource searchConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: foundryProject
  name: searchConnectionName
  properties: {
    category: 'CognitiveSearch'
    target: 'https://${search.name}.search.windows.net'
    authType: 'AAD'
    isSharedToAll: true
    metadata: { ApiType: 'Azure', ResourceId: search.id, location: searchLocation }
  }
}

output foundryAccountName string = foundryAccount.name
output foundryProjectName string = foundryProject.name
output foundryAccountId string = foundryAccount.id
output projectPrincipalId string = projectPrincipalId
output storageAccountName string = storage.name
output cosmosAccountName string = cosmos.name
output searchServiceName string = search.name
output connections array = [ storageConnection.name, cosmosConnection.name, searchConnection.name ]
