targetScope = 'resourceGroup'

@description('Name of the Azure AI Document Intelligence account to create.')
param documentIntelligenceAccountName string

@description('Azure region for the Azure AI Document Intelligence account.')
param location string

@description('SKU for the Azure AI Document Intelligence account.')
@allowed([
  'F0'
  'S0'
])
param skuName string = 'S0'

@description('Tags to apply to the Azure AI Document Intelligence account.')
param tags object = {}

@description('Desired public network access setting for the account.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

resource documentIntelligenceAccount 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: documentIntelligenceAccountName
  location: location
  kind: 'FormRecognizer'
  sku: {
    name: skuName
  }
  properties: {
    customSubDomainName: documentIntelligenceAccountName
    publicNetworkAccess: publicNetworkAccess
  }
  tags: tags
}

output documentIntelligenceAccountId string = documentIntelligenceAccount.id
output documentIntelligenceAccountName string = documentIntelligenceAccount.name
output documentIntelligenceEndpoint string = documentIntelligenceAccount.properties.endpoint

@secure()
output documentIntelligenceKey string = documentIntelligenceAccount.listKeys().key1
