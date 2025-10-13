targetScope = 'resourceGroup'

@description('Name for the role assignment (GUID expected).')
param roleAssignmentName string

@description('Azure AI Foundry (Azure OpenAI) account name that defines the role assignment scope.')
param openAiAccountName string

@description('Principal ID to grant access (e.g., search service managed identity).')
param principalId string

@description('Role definition ID to assign.')
param roleDefinitionId string

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = {
  name: openAiAccountName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: roleAssignmentName
  scope: openAiAccount
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

output roleAssignmentId string = roleAssignment.id
