targetScope = 'resourceGroup'

@description('Name of the existing Azure AI Search service to reference.')
param searchServiceName string

@description('DNS suffix for the Azure AI Search service endpoint.')
param endpointSuffix string = '.search.windows.net'

resource searchService 'Microsoft.Search/searchServices@2024-06-01-preview' existing = {
  name: searchServiceName
}

output searchServiceId string = searchService.id
output searchServiceEndpoint string = 'https://${searchService.name}${endpointSuffix}'
output searchServicePrincipalId string = searchService.identity.principalId
