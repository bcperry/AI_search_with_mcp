targetScope = 'resourceGroup'

@description('Name for the role assignment (GUID expected).')
param roleAssignmentName string

@description('Azure AI Search service name that defines the role assignment scope.')
param searchServiceName string

@description('Principal ID to grant access.')
param principalId string

@description('Role definition ID to assign.')
param roleDefinitionId string

resource searchService 'Microsoft.Search/searchServices@2023-11-01' existing = {
  name: searchServiceName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: roleAssignmentName
  scope: searchService
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

output roleAssignmentId string = roleAssignment.id
