@description('Azure region for the workspace. Should match the App Insights / APIM region.')
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

@description('Name of the existing APIM gateway (Chapter 02) to send diagnostics from.')
param apimName string

@description('Name of the existing Application Insights component (Chapter 02) that receives agent telemetry.')
param appInsightsName string

@description('Name of the existing Standard Foundry account (Chapter 01a) to attach the guardrail RAI policy to.')
param foundryAccountName string

@description('Log Analytics workspace retention in days.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('Create the custom agent-guardrail RAI content-filter policy. It is created but not applied to any deployment.')
param deployGuardrailPolicy bool = true

var namePrefix = '${toLower(replace(workloadName, '_', '-'))}-${environment}'
var workspaceName = '${namePrefix}-law'
var commonTags = {
  workload: workloadName
  environment: environment
  chapter: '15-observability'
  managedBy: 'Bicep'
}

// Dedicated, queryable Log Analytics workspace for gateway logs and dashboards.
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: commonTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Reference existing resources without redeploying them.
resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' existing = {
  name: apimName
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: foundryAccountName
}

// Route APIM gateway logs and metrics into the workspace so ApiManagementGatewayLogs is populated.
resource apimDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'apim-diagnostics'
  scope: apim
  properties: {
    workspaceId: workspace.id
    logs: [
      {
        category: 'GatewayLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// Monitoring dashboard. Workbook names must be GUIDs; derive a stable one from the RG.
resource workbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceGroup().id, 'agent-observability-workbook')
  location: location
  tags: commonTags
  kind: 'shared'
  properties: {
    displayName: 'Agent Platform Observability'
    category: 'workbook'
    sourceId: appInsights.id
    serializedData: replace(replace(loadTextContent('workbook.json'), '__APPINSIGHTS_ID__', appInsights.id), '__WORKSPACE_ID__', workspace.id)
  }
}

// Custom guardrail content-filter policy: DefaultV2 baseline plus blocking Prompt Shields
// (jailbreak + indirect/document attacks). Created only; apply it to a deployment via deploy.ps1.
resource guardrailPolicy 'Microsoft.CognitiveServices/accounts/raiPolicies@2024-10-01' = if (deployGuardrailPolicy) {
  parent: foundryAccount
  name: 'agent-guardrail-v1'
  properties: {
    basePolicyName: 'Microsoft.DefaultV2'
    mode: 'Blocking'
    contentFilters: [
      {
        name: 'Violence'
        blocking: true
        enabled: true
        severityThreshold: 'Medium'
        source: 'Prompt'
      }
      {
        name: 'Violence'
        blocking: true
        enabled: true
        severityThreshold: 'Medium'
        source: 'Completion'
      }
      {
        name: 'Hate'
        blocking: true
        enabled: true
        severityThreshold: 'Medium'
        source: 'Prompt'
      }
      {
        name: 'Hate'
        blocking: true
        enabled: true
        severityThreshold: 'Medium'
        source: 'Completion'
      }
      {
        name: 'Sexual'
        blocking: true
        enabled: true
        severityThreshold: 'Medium'
        source: 'Prompt'
      }
      {
        name: 'Sexual'
        blocking: true
        enabled: true
        severityThreshold: 'Medium'
        source: 'Completion'
      }
      {
        name: 'Selfharm'
        blocking: true
        enabled: true
        severityThreshold: 'Medium'
        source: 'Prompt'
      }
      {
        name: 'Selfharm'
        blocking: true
        enabled: true
        severityThreshold: 'Medium'
        source: 'Completion'
      }
      {
        name: 'Jailbreak'
        blocking: true
        enabled: true
        source: 'Prompt'
      }
      {
        name: 'Indirect Attack'
        blocking: true
        enabled: true
        source: 'Prompt'
      }
    ]
  }
}

output workspaceId string = workspace.id
output workspaceName string = workspace.name
output workbookId string = workbook.id
output guardrailPolicyName string = deployGuardrailPolicy ? guardrailPolicy.name : ''
