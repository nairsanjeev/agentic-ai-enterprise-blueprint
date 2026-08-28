// Chapter 06 — Foundry IQ Knowledge Base (grounding infrastructure).
//
// Foundry IQ grounds agents on your documents via a knowledge index (vector store in Azure AI Search,
// embeddings from a text-embedding model, documents in Blob Storage). The knowledge index itself is a
// data-plane object created from the private Foundry project (portal/SDK inside the VNet) — it can't be
// expressed in ARM. This template provisions the two management-plane prerequisites:
//   1. the embedding model deployment on the Standard Foundry account
//   2. the knowledge-base blob container the index reads from
//
// The Standard project already has the AI Search vector store and the storage connection (Chapter 01a).

targetScope = 'resourceGroup'

@description('Existing Standard Foundry account (network-injected) that hosts the models.')
param foundryAccountName string = 'agent-blueprint-dev-foundry-std-vlpnxwtn'

@description('Existing agent storage account that holds the knowledge-base documents.')
param storageAccountName string = 'ststdfbconcwrg7ntw'

@description('Blob container that holds the knowledge documents.')
param knowledgeContainerName string = 'knowledge-base'

@description('Embedding model to deploy for indexing.')
param embeddingModelName string = 'text-embedding-3-small'

@description('Embedding model version.')
param embeddingModelVersion string = '1'

@description('Embedding capacity in thousands of tokens per minute.')
@minValue(1)
param embeddingCapacity int = 50

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' existing = {
  name: storageAccountName
}

// Embedding model used by the knowledge index to vectorize documents and queries.
resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: foundryAccount
  name: embeddingModelName
  sku: {
    name: 'GlobalStandard'
    capacity: embeddingCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: embeddingModelName
      version: embeddingModelVersion
    }
  }
}

// Container that Foundry IQ reads documents from. Created via ARM so it works despite the storage
// account's private data plane. Upload documents separately from inside the VNet.
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2025-01-01' existing = {
  parent: storageAccount
  name: 'default'
}

resource knowledgeContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-01-01' = {
  parent: blobService
  name: knowledgeContainerName
  properties: {
    publicAccess: 'None'
  }
}

output embeddingDeploymentName string = embeddingDeployment.name
output knowledgeContainerName string = knowledgeContainer.name
output storageAccountName string = storageAccount.name
output nextStep string = 'Upload documents to the knowledge-base container from inside the VNet, then create the knowledge index in the Foundry portal (Knowledge > Create Knowledge Index) or via the Python SDK.'
