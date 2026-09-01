// STEP 00 — LAB ONLY: simulate the VNet that Zava would provide.
//
// Do NOT run this template in the real Zava environment. The real VNet is customer-owned.
// This lab template creates the supplied /25 and the two already-occupied /29 subnets so
// the remaining address space can be tested before workload deployment.
//
// Address plan for 10.75.139.128/25 (10.75.139.128–10.75.139.255):
//   10.75.139.128/29  dmzsubnet-1       existing; 8 total / 3 Azure-usable addresses
//   10.75.139.136/29  hybridsubnet-1    existing; 8 total / 3 Azure-usable addresses
//   10.75.139.144/28  reserved for the private-endpoint subnet created in Step 01
//   10.75.139.160/27  reserved for the Foundry agent subnet created in Step 01
//   10.75.139.192/26  remains unallocated
//
// The supplied text said dmzsubnet-1 was 10.75.128/29. That address is outside the
// 10.75.139.128/25 VNet. This simulation uses 10.75.139.128/29, which matches the
// stated three usable IPs and sits directly before hybridsubnet-1.

targetScope = 'resourceGroup'

param location string = 'eastus'
param vnetName string = 'azr-133-eastus'

var commonTags = {
  customer: 'Zava'
  purpose: 'customer-network-simulation'
  managedBy: 'Bicep'
}

resource customerVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: commonTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.75.139.128/25'
      ]
    }
    // Only the two customer-occupied subnets are created here. Step 01 adds the two
    // Foundry-specific subnets without changing these existing allocations.
    subnets: [
      {
        name: 'dmzsubnet-1'
        properties: {
          addressPrefix: '10.75.139.128/29'
        }
      }
      {
        name: 'hybridsubnet-1'
        properties: {
          addressPrefix: '10.75.139.136/29'
        }
      }
    ]
  }
}

output vnetResourceId string = customerVnet.id
output addressSpace string = customerVnet.properties.addressSpace.addressPrefixes[0]
output warning string = 'LAB ONLY. In Zava, reference the customer-owned VNet and do not deploy Step 00.'
