// STEP 05 — Create the one-time Standard Agent capability hosts.
//
// Run this only after Step 04 succeeds, all four private endpoints are Approved, private
// DNS resolves Storage/Cosmos/Search from the VNet, and project RBAC roles are visible.
//
// WARNING: capability-host creation is not reliably idempotent. Do not blindly rerun this
// deployment after a partial failure. First query both hosts with the validation commands
// in README.md and create only the missing host during recovery.

targetScope = 'resourceGroup'

param workloadName string = 'zava'
param environment string = 'dev'
param networkResourceGroupName string
param vnetName string = 'azr-133-eastus'
param agentSubnetName string = 'snet-zava-foundry-agent'

var prefix = '${toLower(workloadName)}-${environment}'
var suffix = take(uniqueString(subscription().subscriptionId, resourceGroup().id, 'zava-standard'), 8)
var foundryAccountName = take('${prefix}-foundry-std-${suffix}', 63)
var foundryProjectName = take('${prefix}-project-std', 63)

resource customerVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
  scope: resourceGroup(networkResourceGroupName)
}
resource agentSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: customerVnet
  name: agentSubnetName
}
resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountName
}
resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: foundryAccount
  name: foundryProjectName
}

// The account host binds Foundry agent execution to Zava's delegated /27 subnet.
resource accountCapabilityHost 'Microsoft.CognitiveServices/accounts/capabilityHosts@2025-06-01' = {
  parent: foundryAccount
  name: '${foundryAccountName}-cap'
  properties: {
    capabilityHostKind: 'Agents'
    customerSubnet: agentSubnet.id
  }
}

// The project host activates customer-owned files, threads/messages, and vectors through
// the three AAD connections created in Step 04.
resource projectCapabilityHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-06-01' = {
  parent: foundryProject
  name: '${foundryProjectName}-cap'
  properties: {
    #disable-next-line BCP037
    capabilityHostKind: 'Agents'
    storageConnections: [ 'agent-storage' ]
    threadStorageConnections: [ 'agent-thread-storage' ]
    vectorStoreConnections: [ 'agent-vector-store' ]
  }
  dependsOn: [
    accountCapabilityHost
  ]
}

output accountCapabilityHostName string = accountCapabilityHost.name
output projectCapabilityHostName string = projectCapabilityHost.name
output nextStep string = 'Wait for both hosts to report Succeeded before deploying a model or creating agents.'
