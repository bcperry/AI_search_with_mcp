targetScope = 'resourceGroup'

@description('Name for the role assignment (GUID expected).')
param roleAssignmentName string

@description('Storage account name that defines the role assignment scope.')
param storageAccountName string

@description('Principal ID to grant access (managed identity of the search service).')
param principalId string

@description('Role definition ID to assign.')
param roleDefinitionId string

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' existing = {
  name: storageAccountName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: roleAssignmentName
  scope: storageAccount
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

output roleAssignmentId string = roleAssignment.id
