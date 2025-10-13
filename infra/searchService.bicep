targetScope = 'resourceGroup'

@description('Name of the Azure AI Search service to create.')
param searchServiceName string

@description('Azure region for the search service.')
param location string

@description('SKU for the Azure AI Search service.')
param sku string

@description('Tags to apply to the search service.')
param tags object = {}

@description('DNS suffix for the Azure AI Search service endpoint.')
param endpointSuffix string = '.search.windows.net'

resource searchService 'Microsoft.Search/searchServices@2020-08-01' = {
  name: searchServiceName
  location: location
  sku: {
    name: sku
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    publicNetworkAccess: 'enabled'
  }
  tags: tags
}

output searchServiceId string = searchService.id
output searchServiceEndpoint string = 'https://${searchService.name}${endpointSuffix}'
output searchServicePrincipalId string = searchService.identity.principalId
