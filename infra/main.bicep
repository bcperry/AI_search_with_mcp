targetScope = 'subscription'

@description('Azure Developer environment name.')
param environmentName string

@description('Azure region for deployment.')
param location string

@description('Requested resource group name supplied by azd.')
param resourceGroupName string

@description('SKU for the Azure AI Search service.')
@allowed([
  'free'
  'basic'
  'standard'
  'standard2'
  'standard3'
  'storage_optimized_l1'
  'storage_optimized_l2'
])
param searchServiceSku string

@description('SKU for the storage account.')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
  'Standard_GZRS'
  'Standard_RAGZRS'
])
param storageAccountSku string

@description('Azure cloud definition name (see `az cloud list`).')
@allowed([
  'AzureCloud'
  'AzureUSGovernment'
  // 'AzureChinaCloud'
  // 'AzureGermanCloud'
])
param cloudName string

var normalizedEnvironmentName = toLower(replace(environmentName, ' ', '-'))
var finalResourceGroupName = resourceGroupName
var userAssignedIdentityName = '${normalizedEnvironmentName}-uami'
var managedIdentityModuleName = '${normalizedEnvironmentName}-uami'
var searchServiceName = '${normalizedEnvironmentName}-search'
var searchServiceModuleName = '${normalizedEnvironmentName}-search-deploy'
var storageAccountModuleName = '${normalizedEnvironmentName}-storage-deploy'
var storageContainerName = 'aisearchdata'
var searchDataSourceName = '${normalizedEnvironmentName}-storage-ds'
var createSearchDataSourceModuleName = '${normalizedEnvironmentName}-datasource-script'
var scriptIdentityRoleAssignmentName = guid(subscription().id, finalResourceGroupName, searchServiceName, userAssignedIdentityName, 'search-service-contributor')
var cloudSuffixes = {
  AzureCloud: 'windows.net'
  AzureChinaCloud: 'azure.cn'
  AzureUSGovernment: 'azure.us'
  AzureGermanCloud: 'microsoftazure.de'
}
var storageSuffixes = {
  AzureCloud: 'windows.net'
  AzureChinaCloud: 'chinacloudapi.cn'
  AzureUSGovernment: 'usgovcloudapi.net'
  AzureGermanCloud: 'cloudapi.de'
}
var resolvedSearchEndpointSuffix = '.search.${cloudSuffixes[cloudName]}'
var resolvedStorageEndpointCoreSuffix = '.core.${storageSuffixes[cloudName]}'
var cleanedEnvironmentName = replace(normalizedEnvironmentName, '-', '')
var storageAccountBaseName = length(cleanedEnvironmentName) > 0 ? cleanedEnvironmentName : 'env'
var storageAccountCandidate = '${storageAccountBaseName}stg'
var storageAccountName = length(storageAccountCandidate) > 24 ? substring(storageAccountCandidate, 0, 24) : storageAccountCandidate

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: finalResourceGroupName
  location: location
  tags: {
    'azd-env-name': environmentName
  }
}

module userAssignedIdentity './managedIdentity.bicep' = {
  name: managedIdentityModuleName
  scope: rg
  params: {
    userAssignedIdentityName: userAssignedIdentityName
    location: location
  }
}

module searchService 'searchService.bicep' = {
  name: searchServiceModuleName
  scope: rg
  params: {
    searchServiceName: searchServiceName
    location: location
    sku: searchServiceSku
    tags: {
      'azd-env-name': environmentName
    }
    endpointSuffix: resolvedSearchEndpointSuffix
  }
}

module storageAccount './storageAccount.bicep' = {
  name: storageAccountModuleName
  scope: rg
  params: {
    storageAccountName: storageAccountName
    location: location
    skuName: storageAccountSku
    tags: {
      'azd-env-name': environmentName
    }
    endpointCoreSuffix: resolvedStorageEndpointCoreSuffix
    containerName: storageContainerName
  }
}

module searchServiceBlobDataReader 'storageAccountRoleAssignment.bicep' = {
  name: '${normalizedEnvironmentName}-search-blob-reader'
  scope: rg
  params: {
    roleAssignmentName: guid(subscription().id, finalResourceGroupName, storageAccountName, searchServiceName, 'blob-data-reader')
    storageAccountName: storageAccountName
    principalId: searchService.outputs.searchServicePrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
  }
}

module scriptIdentitySearchContributor './searchServiceRoleAssignment.bicep' = {
  name: '${normalizedEnvironmentName}-script-search-contrib'
  scope: rg
  params: {
    roleAssignmentName: scriptIdentityRoleAssignmentName
    searchServiceName: searchServiceName
    principalId: userAssignedIdentity.outputs.userAssignedIdentityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
  }
}

module createSearchDataSource './createSearchDataSource.bicep' = {
  name: createSearchDataSourceModuleName
  scope: rg
  params: {
    location: location
    searchServiceName: searchServiceName
    dataSourceName: searchDataSourceName
    containerName: storageContainerName
    storageAccountResourceId: storageAccount.outputs.storageAccountId
    searchServiceEndpoint: searchService.outputs.searchServiceEndpoint
    resourceGroupName: finalResourceGroupName
    userAssignedIdentityResourceId: userAssignedIdentity.outputs.userAssignedIdentityId
    userAssignedIdentityClientId: userAssignedIdentity.outputs.userAssignedIdentityClientId
    cloudName: cloudName
    subscriptionId: subscription().subscriptionId
    tenantId: subscription().tenantId
  }
  dependsOn: [
    scriptIdentitySearchContributor
    searchServiceBlobDataReader
  ]
}

output RESOURCE_GROUP_ID string = rg.id
output REQUESTED_RESOURCE_GROUP_NAME string = resourceGroupName
output USER_ASSIGNED_IDENTITY_ID string = userAssignedIdentity.outputs.userAssignedIdentityId
output SEARCH_SERVICE_ID string = searchService.outputs.searchServiceId
output SEARCH_SERVICE_NAME string = searchServiceName
output SEARCH_SERVICE_ENDPOINT string = searchService.outputs.searchServiceEndpoint
output SEARCH_SERVICE_ENDPOINT_SUFFIX string = resolvedSearchEndpointSuffix
output CLOUD_NAME string = cloudName
output STORAGE_ACCOUNT_ID string = storageAccount.outputs.storageAccountId
output STORAGE_ACCOUNT_NAME string = storageAccountName
output STORAGE_ACCOUNT_BLOB_ENDPOINT string = storageAccount.outputs.blobEndpoint
output STORAGE_ACCOUNT_TABLE_ENDPOINT string = storageAccount.outputs.tableEndpoint
output STORAGE_ACCOUNT_QUEUE_ENDPOINT string = storageAccount.outputs.queueEndpoint
output STORAGE_ACCOUNT_FILE_ENDPOINT string = storageAccount.outputs.fileEndpoint
output STORAGE_ACCOUNT_CONTAINER_NAME string = storageContainerName
output SEARCH_DATA_SOURCE_NAME string = searchDataSourceName
