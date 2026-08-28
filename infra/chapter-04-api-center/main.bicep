// Chapter 04 — Azure API Center (enterprise catalog for APIs, MCP servers, skills).
//
// This template provisions the API Center and wires it to the existing APIM gateway so APIs and MCP
// servers sync into the catalog automatically. It replaces the ad-hoc CLI steps with reproducible IaC.
//
// Not in this template (cannot be expressed in ARM/Bicep):
//   - The managed developer-portal enablement and its Entra app registration (Entra apps aren't ARM).
//     deploy.ps1 creates the sign-in app; the portal is enabled/ wired in the Azure portal.
//   - Skill *asset* registration (portal action, per the private-skill-catalog docs).

targetScope = 'resourceGroup'

@description('Azure region for the API Center. API Center is not available in every region; eastus is used by default.')
param location string = 'eastus'

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

@description('Name of the existing APIM instance to link for automatic API/MCP sync.')
param apimName string = 'apim-agent-blueprint-dev-a5jiq4re'

@description('Object ID (principal) granted Azure API Center Data Reader so it can discover the catalog. Empty skips the assignment.')
param catalogReaderPrincipalId string = ''

@description('Principal type for the catalog reader role assignment.')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param catalogReaderPrincipalType string = 'User'

@description('Create the governance metadata schemas (owning-team, data-classification, agent-protocol).')
param deployMetadataSchemas bool = true

@description('Register the sample typed assets (Packing Advisor agent + Travel Packing Guidelines skill) so they appear under the portal Agents/Skills tabs.')
param deploySampleAssets bool = true

@description('Public Git URL of the skill SKILL.md, shown as the skill source in the catalog.')
param skillSourceUrl string = 'https://github.com/nairsanjeev/agentic-ai-enterprise-blueprint/blob/master/skills/travel-packing-guidelines/SKILL.md'

@description('Extra sample catalog assets (kind = mcp | agent | skill | plugin) to populate the portal tabs for demos.')
param sampleCatalogAssets array = [
  { name: 'hr-directory-mcp', title: 'HR Directory MCP', kind: 'mcp', description: 'MCP server for employee lookup, org chart, and reporting lines. Sample.' }
  { name: 'expense-tools-mcp', title: 'Expense Tools MCP', kind: 'mcp', description: 'MCP server to submit and validate expense reports against policy. Sample.' }
  { name: 'travel-booking-agent', title: 'Travel Booking Agent', kind: 'agent', description: 'A2A agent that books policy-compliant flights and hotels. Sample.' }
  { name: 'it-helpdesk-agent', title: 'IT Helpdesk Agent', kind: 'agent', description: 'A2A agent that triages IT tickets and coordinates access resets. Sample.' }
  { name: 'brand-voice-guidelines', title: 'Brand Voice Guidelines', kind: 'skill', description: 'Tone and messaging rules an agent applies to customer comms. Sample.' }
  { name: 'incident-triage-runbook', title: 'Incident Triage Runbook', kind: 'skill', description: 'Severity classification and escalation steps. Sample.' }
  { name: 'servicenow-connector', title: 'ServiceNow Connector', kind: 'plugin', description: 'Plugin to create and update ServiceNow incidents. Sample.' }
  { name: 'salesforce-connector', title: 'Salesforce Connector', kind: 'plugin', description: 'Plugin to read and update Salesforce CRM opportunities. Sample.' }
]

var normalizedWorkloadName = toLower(replace(workloadName, '_', '-'))
var namePrefix = '${normalizedWorkloadName}-${environment}'
// Names match the already-provisioned resources so a redeploy adopts them (idempotent).
var apiCenterName = 'apic-${namePrefix}'
var identityName = 'id-apic-${normalizedWorkloadName}'

// Built-in role definition IDs.
var apimServiceReaderRoleId = '71522526-b88f-4d52-b57f-d31fc3546d0d' // API Management Service Reader Role
var apiCenterDataReaderRoleId = 'c7244dfb-f447-457d-b2ba-3999044d1706' // Azure API Center Data Reader

var commonTags = {
  workload: workloadName
  environment: environment
  chapter: '04-api-center'
  managedBy: 'Bicep'
}

// Existing APIM the catalog links to.
resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

// Identity API Center uses to read APIM during sync.
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: commonTags
}

// Let the identity read the APIM instance so sync can enumerate APIs and MCP servers.
resource apimReaderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: apim
  name: guid(apim.id, identity.id, apimServiceReaderRoleId)
  properties: {
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', apimServiceReaderRoleId)
  }
}

resource apiCenter 'Microsoft.ApiCenter/services@2024-06-01-preview' = {
  name: apiCenterName
  location: location
  tags: commonTags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identity.id}': {}
    }
  }
}

// The 'default' workspace is created automatically with the service.
resource workspace 'Microsoft.ApiCenter/services/workspaces@2024-06-01-preview' existing = {
  parent: apiCenter
  name: 'default'
}

// Live link to APIM — APIs and MCP servers sync into the catalog.
resource apimSource 'Microsoft.ApiCenter/services/workspaces/apiSources@2024-06-01-preview' = {
  parent: workspace
  name: 'apim-link'
  properties: {
    azureApiManagementSource: {
      resourceId: apim.id
      msiResourceId: identity.id
    }
    importSpecification: 'always'
  }
  dependsOn: [
    apimReaderAssignment
  ]
}

// Governance metadata schemas applied to catalog APIs.
resource mdOwningTeam 'Microsoft.ApiCenter/services/metadataSchemas@2024-06-01-preview' = if (deployMetadataSchemas) {
  parent: apiCenter
  name: 'owning-team'
  properties: {
    schema: '{"type":"string","title":"Owning Team","enum":["travel","hr","finance","engineering","platform"]}'
    assignedTo: [
      {
        entity: 'api'
        required: false
      }
    ]
  }
}

resource mdDataClassification 'Microsoft.ApiCenter/services/metadataSchemas@2024-06-01-preview' = if (deployMetadataSchemas) {
  parent: apiCenter
  name: 'data-classification'
  properties: {
    schema: '{"type":"string","title":"Data Classification","enum":["public","internal","confidential","restricted"]}'
    assignedTo: [
      {
        entity: 'api'
        required: false
      }
    ]
  }
}

resource mdAgentProtocol 'Microsoft.ApiCenter/services/metadataSchemas@2024-06-01-preview' = if (deployMetadataSchemas) {
  parent: apiCenter
  name: 'agent-protocol'
  properties: {
    schema: '{"type":"string","title":"Agent Protocol","enum":["mcp","a2a","rest","graphql"]}'
    assignedTo: [
      {
        entity: 'api'
        required: false
      }
    ]
  }
}

// Typed catalog assets — appear under the portal's Agents and Skills tabs (kind drives the category).
resource skillAsset 'Microsoft.ApiCenter/services/workspaces/apis@2024-06-01-preview' = if (deploySampleAssets) {
  parent: workspace
  name: 'travel-packing-guidelines'
  properties: {
    title: 'Travel Packing Guidelines'
    // 'skill'/'agent' aren't in the Bicep type enum yet but are valid at runtime.
    #disable-next-line BCP036
    kind: 'skill'
    description: 'Organizational guidelines an agent follows when producing travel packing checklists.'
    #disable-next-line BCP073
    lifecycleStage: 'production'
    externalDocumentation: [
      {
        title: 'SKILL.md source'
        url: skillSourceUrl
      }
    ]
  }
}

resource agentAsset 'Microsoft.ApiCenter/services/workspaces/apis@2024-06-01-preview' = if (deploySampleAssets) {
  parent: workspace
  name: 'packing-advisor-agent'
  properties: {
    title: 'Packing Advisor Agent'
    #disable-next-line BCP036
    kind: 'agent'
    description: 'A2A-compliant agent that returns a practical packing checklist for a destination. JSON-RPC over the governed APIM gateway.'
    #disable-next-line BCP073
    lifecycleStage: 'production'
    externalDocumentation: [
      {
        title: 'A2A agent card'
        url: 'https://${apimName}.azure-api.net/.well-known/agent-card.json'
      }
    ]
  }
}

// Extra sample assets so the portal Agents / MCP servers / Skills / Plugins tabs are populated.
resource sampleAssetResources 'Microsoft.ApiCenter/services/workspaces/apis@2024-06-01-preview' = [for a in sampleCatalogAssets: if (deploySampleAssets) {
  parent: workspace
  name: a.name
  properties: {
    title: a.title
    #disable-next-line BCP036
    kind: a.kind
    description: a.description
    #disable-next-line BCP073
    lifecycleStage: 'production'
  }
}]

// Grant a human/group discovery access to the catalog (used by the Foundry skill catalog + portal).
resource catalogReaderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(catalogReaderPrincipalId)) {
  scope: apiCenter
  name: guid(apiCenter.id, catalogReaderPrincipalId, apiCenterDataReaderRoleId)
  properties: {
    principalId: catalogReaderPrincipalId
    principalType: catalogReaderPrincipalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', apiCenterDataReaderRoleId)
  }
}

output apiCenterName string = apiCenter.name
output apiCenterId string = apiCenter.id
output dataApiHostname string = '${apiCenterName}.data.${location}.azure-apicenter.ms'
output identityName string = identity.name
output identityPrincipalId string = identity.properties.principalId
output portalUrl string = 'https://${apiCenterName}.portal.${location}.azure-apicenter.ms'
output nextStep string = 'Enable the managed developer portal in the Azure portal and wire the sign-in Entra app created by deploy.ps1.'
