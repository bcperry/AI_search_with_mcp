targetScope = 'resourceGroup'

@description('Name of the storage account to create.')
param storageAccountName string

@description('Azure region for the storage account.')
param location string

@description('SKU name for the storage account.')
param skuName string

@description('Tags to apply to the storage account.')
param tags object = {}

@description('Core DNS suffix for storage account endpoints (e.g. .core.windows.net).')
param endpointCoreSuffix string

@description('Name of the blob container to provision for AI Search ingestion.')
param containerName string

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: skuName
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
  tags: tags
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = {
  name: 'default'
  parent: storageAccount
}

resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  name: containerName
  parent: blobService
  properties: {
    publicAccess: 'None'
  }
}

output storageAccountId string = storageAccount.id
output blobEndpoint string = 'https://${storageAccount.name}.blob${endpointCoreSuffix}'
output tableEndpoint string = 'https://${storageAccount.name}.table${endpointCoreSuffix}'
output queueEndpoint string = 'https://${storageAccount.name}.queue${endpointCoreSuffix}'
output fileEndpoint string = 'https://${storageAccount.name}.file${endpointCoreSuffix}'
output storageContainerName string = containerName
