@description('Azure region. Must match the reused VNet and the Foundry account region.')
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

@description('Name of the existing VNet from Chapter 01 to reuse.')
param existingVnetName string = 'agent-blueprint-dev-vnet'

@description('New subnet for APIM Premium v2 VNet injection. Must be free within the reused VNet address space.')
param apimSubnetPrefix string = '192.168.2.0/24'

@description('Name of the existing Foundry (AIServices) account to use as the model backend.')
param foundryAccountName string

@description('APIM publisher organization name shown in developer portal and notifications.')
param publisherName string = 'Enterprise AI Platform'

@description('APIM publisher email for service notifications.')
param publisherEmail string = 'ai-platform@example.com'

@description('APIM SKU. Developer uses classic VNet injection (needs an NSG, no subnet delegation); Premiumv2 uses v2 injection (delegated subnet).')
@allowed([
  'Developer'
  'Premiumv2'
])
param apimSkuName string = 'Developer'

@description('APIM scale units. Developer tier only supports 1.')
@minValue(1)
param apimCapacity int = 1

var normalizedWorkloadName = toLower(replace(workloadName, '_', '-'))
var namePrefix = '${normalizedWorkloadName}-${environment}'
var uniqueSuffix = take(uniqueString(subscription().subscriptionId, resourceGroup().id), 8)
var apimName = take('apim-${namePrefix}-${uniqueSuffix}', 50)
var appInsightsName = '${namePrefix}-gateway-appi'
var isV2Sku = apimSkuName == 'Premiumv2'

var commonTags = {
  workload: workloadName
  environment: environment
  chapter: '02-ai-gateway'
  managedBy: 'Bicep'
}

// Reference the VNet created in Chapter 01 without redeploying it.
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: existingVnetName
}

// NSG with the rules classic APIM (stv2) VNet injection requires: management endpoint and load balancer.
resource apimNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${namePrefix}-apim-nsg'
  location: location
  tags: commonTags
  properties: {
    securityRules: [
      {
        name: 'Allow-APIM-Management-Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'ApiManagement'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '3443'
        }
      }
      {
        name: 'Allow-LoadBalancer-Inbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '6390'
        }
      }
      {
        name: 'Allow-Client-Inbound'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [
            '80'
            '443'
          ]
        }
      }
      {
        name: 'Allow-Storage-Outbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Storage'
          destinationPortRange: '443'
        }
      }
      {
        name: 'Allow-Sql-Outbound'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'SQL'
          destinationPortRange: '1433'
        }
      }
      {
        name: 'Allow-KeyVault-Outbound'
        properties: {
          priority: 120
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureKeyVault'
          destinationPortRange: '443'
        }
      }
      {
        name: 'Allow-EntraID-Outbound'
        properties: {
          priority: 130
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureActiveDirectory'
          destinationPortRange: '443'
        }
      }
      {
        name: 'Allow-Monitor-Outbound'
        properties: {
          priority: 140
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureMonitor'
          destinationPortRanges: [
            '443'
            '1886'
          ]
        }
      }
    ]
  }
}

// Add the APIM subnet as a standalone child so Chapter 01's subnets are left intact.
// Delegation is only valid for the v2 tiers; classic injection (Developer) must not delegate.
resource apimSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: virtualNetwork
  name: 'snet-apim'
  properties: {
    addressPrefix: apimSubnetPrefix
    networkSecurityGroup: {
      id: apimNsg.id
    }
    delegations: isV2Sku ? [
      {
        name: 'apim-delegation'
        properties: {
          serviceName: 'Microsoft.ApiManagement/service'
        }
      }
    ] : []
  }
}

// Existing Foundry account used as the private model backend for the gateway.
resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountName
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  tags: commonTags
  properties: {
    Application_Type: 'web'
  }
}

// APIM Premium v2 with Internal VNet injection: the gateway is reachable only at a private IP.
resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apimName
  location: location
  tags: commonTags
  sku: {
    name: apimSkuName
    capacity: apimCapacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherName: publisherName
    publisherEmail: publisherEmail
    virtualNetworkType: 'Internal'
    virtualNetworkConfiguration: {
      subnetResourceId: apimSubnet.id
    }
  }
}

resource apimLogger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = {
  parent: apim
  name: 'appinsights'
  properties: {
    loggerType: 'applicationInsights'
    description: 'AI gateway telemetry'
    resourceId: appInsights.id
    credentials: {
      instrumentationKey: appInsights.properties.InstrumentationKey
    }
  }
}

// Built-in Cognitive Services OpenAI User role — lets APIM's managed identity call the model backend.
var openAiUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

resource apimToFoundryRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundryAccount
  name: guid(foundryAccount.id, apim.id, openAiUserRoleId)
  properties: {
    principalId: apim.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', openAiUserRoleId)
  }
}

// Private DNS zone for the Internal APIM gateway hostnames. A records are added post-deploy.
resource apimDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'azure-api.net'
  location: 'global'
  tags: commonTags
}

resource apimDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: apimDnsZone
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

output apimName string = apim.name
output apimResourceId string = apim.id
output apimPrincipalId string = apim.identity.principalId
output appInsightsName string = appInsights.name
output apimDnsZoneName string = apimDnsZone.name
output foundryAccountName string = foundryAccount.name
output gatewayHostname string = '${apim.name}.azure-api.net'
