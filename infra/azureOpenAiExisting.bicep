targetScope = 'resourceGroup'

@description('Name of the existing Azure AI Foundry (Azure OpenAI) account to reference.')
param openAiAccountName string

@description('Name of the existing embeddings deployment within the Azure AI Foundry account.')
param embeddingsDeploymentName string

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = {
  name: openAiAccountName
}

resource openAiEmbeddingsDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' existing = {
  name: embeddingsDeploymentName
  parent: openAiAccount
}

output openAiAccountId string = openAiAccount.id
output openAiAccountEndpoint string = openAiAccount.properties.endpoint
output openAiAccountName string = openAiAccount.name
output openAiEmbeddingsDeploymentId string = openAiEmbeddingsDeployment.id
output openAiEmbeddingsDeploymentName string = embeddingsDeploymentName
output openAiEmbeddingsDeploymentModel string = openAiEmbeddingsDeployment.properties.model.name
