targetScope = 'resourceGroup'

@description('Name of the Log Analytics workspace to create.')
param workspaceName string

@description('Azure region for the Log Analytics workspace.')
param location string

@description('Tags to apply to the workspace.')
param tags object = {}

@description('Number of days to retain data in the workspace.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
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

output workspaceId string = workspace.id
output workspaceName string = workspace.name
