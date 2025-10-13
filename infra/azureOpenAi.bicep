targetScope = 'resourceGroup'

@description('Name of the Azure AI Foundry (Azure OpenAI) account to create.')
param openAiAccountName string

@description('Custom subdomain prefix to use for the Azure AI Foundry endpoint (e.g., https://<prefix>.openai.azure.com).')
param customSubDomainName string

@description('Azure region for the Azure AI Foundry account.')
param location string

@description('SKU for the Azure AI Foundry account.')
@allowed([
  'S0'
])
param skuName string = 'S0'

@description('Tags to apply to the Azure AI Foundry account.')
param tags object = {}

@description('Desired public network access setting for the account.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Name of the deployment to provision within the Azure AI Foundry account.')
param deploymentName string

@description('Model name for the deployment (e.g., gpt-4o).')
param modelName string

@description('Model version to deploy.')
param modelVersion string

@description('Manual scale capacity (throughput units) for the deployment.')
@minValue(1)
param capacity int = 1

@description('Name of the embeddings deployment to provision within the Azure AI Foundry account.')
param embeddingsDeploymentName string

@description('Model name for the embeddings deployment (e.g., text-embedding-ada-002).')
param embeddingsModelName string = 'text-embedding-ada-002'

@description('Model version to deploy for embeddings.')
param embeddingsModelVersion string = '2'

@description('Manual scale capacity (throughput units) for the embeddings deployment.')
@minValue(1)
param embeddingsCapacity int = 10

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: openAiAccountName
  location: location
  kind: 'OpenAI'
  sku: {
    name: skuName
  }
  properties: {
    customSubDomainName: customSubDomainName
    publicNetworkAccess: publicNetworkAccess
  }
  tags: tags
}

resource openAiDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  name: deploymentName
  parent: openAiAccount
  properties: {
    model: {
      name: modelName
      format: 'OpenAI'
      version: modelVersion
    }
    raiPolicyName: ''
  }
  sku: {
    name: 'Standard'
    capacity: capacity
  }
}

resource openAiEmbeddingsDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  name: embeddingsDeploymentName
  parent: openAiAccount
  properties: {
    model: {
      name: embeddingsModelName
      format: 'OpenAI'
      version: embeddingsModelVersion
    }
    raiPolicyName: ''
  }
  sku: {
    name: 'Standard'
    capacity: embeddingsCapacity
  }
}

output openAiAccountId string = openAiAccount.id
output openAiAccountEndpoint string = openAiAccount.properties.endpoint
output openAiAccountName string = openAiAccount.name
output openAiDeploymentId string = openAiDeployment.id
output openAiDeploymentName string = deploymentName
output openAiDeploymentModel string = modelName
output openAiEmbeddingsDeploymentId string = openAiEmbeddingsDeployment.id
output openAiEmbeddingsDeploymentName string = embeddingsDeploymentName
output openAiEmbeddingsDeploymentModel string = embeddingsModelName
