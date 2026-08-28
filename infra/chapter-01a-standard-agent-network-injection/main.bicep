// Chapter 01a — Foundry Standard Agent Setup WITH network injection (BYO VNet egress).
//
// Why this module exists
// ----------------------
// Chapter 01 creates a private Foundry account/project, but agents built on it still run
// their tool-call egress on the Microsoft-managed network. That is why calling an internal
// (VNet-only) endpoint such as an internal APIM gateway fails with
//   "The host name could not be resolved from the selected network path".
//
// Foundry Agent Service only injects agent compute into your delegated subnet when the
// account is a *Standard Agent Setup* (bring-your-own Cosmos DB + AI Search + Storage,
// wired through a capability host) AND the account carries a `networkInjections` block.
// This module provisions exactly that, reusing the Chapter 01 VNet and subnets.
//
// IMPORTANT: network injection cannot be added to an account that already has agents.
// This module therefore stands up a NEW Standard account/project alongside Chapter 01.

targetScope = 'resourceGroup'

@description('Azure region. Must match the Chapter 01 VNet region.')
param location string = resourceGroup().location

@description('Region for the BYO Azure AI Search service. Override when the VNet region is out of Search capacity. A private endpoint in the VNet still reaches it cross-region.')
param searchLocation string = location

@description('Short workload name used in resource names.')
@minLength(2)
@maxLength(20)
param workloadName string = 'agent-blueprint'

@description('Deployment environment name used in tags and names.')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Name of the existing Chapter 01 VNet that hosts the delegated and private-endpoint subnets.')
param existingVnetName string = 'agent-blueprint-dev-vnet'

@description('Existing subnet delegated to Microsoft.App/environments that agent compute is injected into.')
param agentSubnetName string = 'snet-foundry'

@description('Existing subnet used for private endpoints.')
param privateEndpointSubnetName string = 'snet-privateendpoints'

@description('Resource IDs of additional VNets (e.g., a peered admin/jumpbox VNet like demovnet) that must resolve the new Cosmos/Search private DNS zones. Without this, hosts in those VNets resolve to public IPs and are denied.')
param additionalLinkedVnetIds array = []

@description('Deploy the gpt-4o model into the new Standard account. Set false when regional quota is unavailable.')
param deployModel bool = true

@description('Model deployment name exposed by the Standard Foundry account.')
param modelDeploymentName string = 'gpt-4o'

@description('gpt-4o model version.')
param modelVersion string = '2024-11-20'

@description('GlobalStandard capacity in thousands of tokens per minute.')
@minValue(1)
param modelCapacity int = 30

@description('Object ID granted the Foundry User role so it can build agents in the new project. Empty skips it.')
param foundryUserPrincipalId string = ''

@description('Principal type for the Foundry User role assignment.')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param foundryUserPrincipalType string = 'User'

// ---------------------------------------------------------------------------
// Names — a distinct 'std' marker keeps these resources separate from Chapter 01
// so both accounts can coexist during migration.
// ---------------------------------------------------------------------------
var normalizedWorkloadName = toLower(replace(workloadName, '_', '-'))
var namePrefix = '${normalizedWorkloadName}-${environment}'
var uniqueSuffix = take(uniqueString(subscription().subscriptionId, resourceGroup().id, 'std-agent'), 8)

var foundryAccountName = take('${namePrefix}-foundry-std-${uniqueSuffix}', 63)
var foundryProjectName = take('${namePrefix}-project-std', 63)
var cosmosAccountName = take('${namePrefix}-cosmos-${uniqueSuffix}', 44)
var searchServiceName = take('${namePrefix}-search-${uniqueSuffix}', 60)
var storageAccountName = take('ststd${uniqueString(subscription().subscriptionId, resourceGroup().id, workloadName, environment, 'std')}', 24)

var storageConnectionName = 'agent-storage'
var cosmosConnectionName = 'agent-thread-storage'
var searchConnectionName = 'agent-vector-store'

var commonTags = {
  workload: workloadName
  environment: environment
  chapter: '01a-standard-agent-network-injection'
  managedBy: 'Bicep'
}

// Built-in role definition IDs used below.
var roleFoundryUser = '53ca6127-db72-4b80-b1b0-d745d6d5456d'
var roleStorageBlobDataOwner = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var roleCosmosDbOperator = '230815da-be43-4aae-9cb4-875f7bd000aa'
var roleSearchIndexDataContributor = '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
var roleSearchServiceContributor = '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
// Cosmos DB built-in *data-plane* SQL role (Data Contributor) — needed so the project
// identity can read/write the thread containers the capability host provisions.
var cosmosDataContributorRoleGuid = '00000000-0000-0000-0000-000000000002'

// ---------------------------------------------------------------------------
// Existing network — reused from Chapter 01.
// ---------------------------------------------------------------------------
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: existingVnetName
}

resource agentSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: virtualNetwork
  name: agentSubnetName
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: virtualNetwork
  name: privateEndpointSubnetName
}

// Foundry private DNS zones already exist from Chapter 01 — reference them.
resource cognitiveServicesDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.cognitiveservices.azure.com'
}

resource openAiDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.openai.azure.com'
}

resource servicesAiDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.services.ai.azure.com'
}

// ---------------------------------------------------------------------------
// New private DNS zones for the Standard-setup dependencies (Cosmos + Search).
// ---------------------------------------------------------------------------
resource cosmosDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.documents.azure.com'
  location: 'global'
  tags: commonTags
}

resource cosmosDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: cosmosDnsZone
  name: 'link-${existingVnetName}'
  location: 'global'
  tags: commonTags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

resource searchDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.search.windows.net'
  location: 'global'
  tags: commonTags
}

resource searchDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: searchDnsZone
  name: 'link-${existingVnetName}'
  location: 'global'
  tags: commonTags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

// Link the new zones to any peered admin/jumpbox VNets (e.g., demovnet) so hosts there resolve
// Cosmos/Search to their private endpoints instead of public IPs.
resource cosmosDnsLinkExtra 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (vnetId, i) in additionalLinkedVnetIds: {
  parent: cosmosDnsZone
  name: 'link-extra-${i}'
  location: 'global'
  tags: commonTags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}]

resource searchDnsLinkExtra 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (vnetId, i) in additionalLinkedVnetIds: {
  parent: searchDnsZone
  name: 'link-extra-${i}'
  location: 'global'
  tags: commonTags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}]

// Blob DNS zone already exists from Chapter 01 — reference it for the new storage account PE.
resource blobDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.blob.${az.environment().suffixes.storage}'
}

// ---------------------------------------------------------------------------
// Bring-your-own dependency: Storage (agent file storage).
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Bring-your-own dependency: Cosmos DB (agent thread / message store).
// ---------------------------------------------------------------------------
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = {
  name: cosmosAccountName
  location: location
  kind: 'GlobalDocumentDB'
  tags: commonTags
  properties: {
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: false
    disableLocalAuth: true
    publicNetworkAccess: 'Disabled'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Bring-your-own dependency: Azure AI Search (agent vector store).
// ---------------------------------------------------------------------------
resource searchService 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: searchServiceName
  location: searchLocation
  tags: commonTags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'standard'
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    disableLocalAuth: true
    publicNetworkAccess: 'disabled'
    authOptions: null
    // Semantic ranker is required by Foundry IQ knowledge bases.
    semanticSearch: 'free'
  }
}

// ---------------------------------------------------------------------------
// The Standard Foundry account WITH network injection.
// networkInjections is what pushes agent compute (and its tool-call egress)
// into snet-foundry, so agents can resolve private DNS zones and reach
// VNet-only endpoints such as the internal APIM gateway.
// ---------------------------------------------------------------------------
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
  identity: {
    type: 'SystemAssigned'
  }
  tags: commonTags
  properties: {
    displayName: '${workloadName} ${environment} (standard)'
    description: 'Chapter 01a Standard Agent Setup with network injection'
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

// ---------------------------------------------------------------------------
// Private endpoints for the new account and its dependencies.
// ---------------------------------------------------------------------------
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
}

resource foundryDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: foundryPrivateEndpoint
  name: 'foundry-dns-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-cognitiveservices-azure-com'
        properties: {
          privateDnsZoneId: cognitiveServicesDnsZone.id
        }
      }
      {
        name: 'privatelink-openai-azure-com'
        properties: {
          privateDnsZoneId: openAiDnsZone.id
        }
      }
      {
        name: 'privatelink-services-ai-azure-com'
        properties: {
          privateDnsZoneId: servicesAiDnsZone.id
        }
      }
    ]
  }
}

resource cosmosPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${cosmosAccountName}'
  location: location
  tags: commonTags
  properties: {
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'cosmos-connection'
        properties: {
          privateLinkServiceId: cosmosAccount.id
          groupIds: [
            'Sql'
          ]
        }
      }
    ]
  }
}

resource cosmosDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: cosmosPrivateEndpoint
  name: 'cosmos-dns-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-documents-azure-com'
        properties: {
          privateDnsZoneId: cosmosDnsZone.id
        }
      }
    ]
  }
}

resource searchPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${searchServiceName}'
  location: location
  tags: commonTags
  properties: {
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'search-connection'
        properties: {
          privateLinkServiceId: searchService.id
          groupIds: [
            'searchService'
          ]
        }
      }
    ]
  }
}

resource searchDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: searchPrivateEndpoint
  name: 'search-dns-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-search-windows-net'
        properties: {
          privateDnsZoneId: searchDnsZone.id
        }
      }
    ]
  }
}

resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${storageAccountName}-blob'
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
}

resource storageDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: storagePrivateEndpoint
  name: 'storage-dns-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-blob'
        properties: {
          privateDnsZoneId: blobDnsZone.id
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Role assignments — the project's managed identity must own the data plane of
// each dependency BEFORE the capability host provisions its containers/indexes.
// ---------------------------------------------------------------------------
var projectPrincipalId = foundryProject.identity.principalId

resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, foundryProject.id, roleStorageBlobDataOwner)
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleStorageBlobDataOwner)
  }
}

resource cosmosOperatorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: cosmosAccount
  name: guid(cosmosAccount.id, foundryProject.id, roleCosmosDbOperator)
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleCosmosDbOperator)
  }
}

resource searchIndexRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: searchService
  name: guid(searchService.id, foundryProject.id, roleSearchIndexDataContributor)
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleSearchIndexDataContributor)
  }
}

resource searchServiceRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: searchService
  name: guid(searchService.id, foundryProject.id, roleSearchServiceContributor)
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleSearchServiceContributor)
  }
}

// Cosmos data-plane access (account-scoped) so the project identity can use the
// thread containers the capability host creates.
resource cosmosDataRoleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-11-15' = {
  parent: cosmosAccount
  name: guid(cosmosAccount.id, foundryProject.id, cosmosDataContributorRoleGuid)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/${cosmosDataContributorRoleGuid}'
    scope: cosmosAccount.id
  }
}

// ---------------------------------------------------------------------------
// Project connections to the three BYO dependencies. Their names are referenced
// by the project capability host below.
// ---------------------------------------------------------------------------
resource storageConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: foundryProject
  name: storageConnectionName
  properties: {
    category: 'AzureStorageAccount'
    target: storageAccount.properties.primaryEndpoints.blob
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: storageAccount.id
      location: location
    }
  }
}

resource cosmosConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: foundryProject
  name: cosmosConnectionName
  properties: {
    category: 'CosmosDB'
    target: cosmosAccount.properties.documentEndpoint
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: cosmosAccount.id
      location: location
    }
  }
}

resource searchConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: foundryProject
  name: searchConnectionName
  properties: {
    category: 'CognitiveSearch'
    target: 'https://${searchServiceName}.search.windows.net'
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: searchService.id
      location: location
    }
  }
}

// ---------------------------------------------------------------------------
// Capability hosts — the account host must exist before the project host.
// The project host binds the three connections, which triggers Foundry to
// provision the agent's storage/threads/vectors inside YOUR resources.
// ---------------------------------------------------------------------------
resource accountCapabilityHost 'Microsoft.CognitiveServices/accounts/capabilityHosts@2025-06-01' = {
  parent: foundryAccount
  name: '${foundryAccountName}-cap'
  properties: {
    // customerSubnet must match the injected agent subnet recorded on the account.
    capabilityHostKind: 'Agents'
    customerSubnet: agentSubnet.id
  }
}

resource projectCapabilityHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-06-01' = {
  parent: foundryProject
  name: '${foundryProjectName}-cap'
  properties: {
    // Bicep types for project capability hosts are stale; these properties are valid at runtime.
    #disable-next-line BCP037
    capabilityHostKind: 'Agents'
    storageConnections: [
      storageConnectionName
    ]
    threadStorageConnections: [
      cosmosConnectionName
    ]
    vectorStoreConnections: [
      searchConnectionName
    ]
  }
  dependsOn: [
    accountCapabilityHost
    storageConnection
    cosmosConnection
    searchConnection
    storageRoleAssignment
    cosmosOperatorRoleAssignment
    cosmosDataRoleAssignment
    searchIndexRoleAssignment
    searchServiceRoleAssignment
  ]
}

// ---------------------------------------------------------------------------
// Optional: grant a human the Foundry User role so they can build agents.
// ---------------------------------------------------------------------------
resource foundryUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(foundryUserPrincipalId)) {
  scope: foundryProject
  name: guid(foundryProject.id, foundryUserPrincipalId, roleFoundryUser)
  properties: {
    principalId: foundryUserPrincipalId
    principalType: foundryUserPrincipalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleFoundryUser)
  }
}

output foundryAccountName string = foundryAccount.name
output foundryProjectName string = foundryProject.name
output foundryProjectResourceId string = foundryProject.id
output foundryEndpoint string = foundryAccount.properties.endpoint
output cosmosAccountName string = cosmosAccount.name
output searchServiceName string = searchService.name
output storageAccountName string = storageAccount.name
output agentSubnetId string = agentSubnet.id
output networkInjectionConfigured bool = true
output nextStep string = 'Recreate your agents and tool connections on this Standard project. Agent tool-call egress now flows through snet-foundry and can reach VNet-only endpoints (e.g., internal APIM).'
