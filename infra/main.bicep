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

@description('SKU name for the App Service plan used to host the MCP application.')
@allowed([
  'P1v3'
  'P2v3'
  'P3v3'
  'S1'
  'S2'
  'S3'
  'B1'
  'B2'
  'B3'
])
param appServicePlanSkuName string = 'P1v3'

@description('SKU tier for the App Service plan used to host the MCP application.')
@allowed([
  'PremiumV3'
  'Standard'
  'Basic'
])
param appServicePlanSkuTier string = 'PremiumV3'

@description('Number of workers allocated to the App Service plan.')
@minValue(1)
param appServicePlanSkuCapacity int = 1

@description('Python runtime version for the App Service Web App.')
@allowed([
  '3.10'
  '3.11'
])
param webAppPythonVersion string = '3.10'

@description('Startup command executed by the Web App when the container starts.')
param webAppStartupCommand string = 'python main.py'

@description('Whether to enable Always On for the Web App hosting the MCP application.')
param webAppAlwaysOn bool = true

@description('Azure cloud definition name (see `az cloud list`).')
@allowed([
  'AzureCloud'
  'AzureUSGovernment'
  // 'AzureChinaCloud'
  // 'AzureGermanCloud'
])
param cloudName string

@description('Model identifier to deploy to Azure AI Foundry.')
param openAiModelName string = 'gpt-4o'

@description('Model version for the Azure AI Foundry deployment.')
param openAiModelVersion string = '2024-11-20'

@description('Throughput units for the Azure AI Foundry deployment.')
@minValue(1)
param openAiDeploymentCapacity int = 10

@description('Embeddings model identifier to deploy to Azure AI Foundry.')
param openAiEmbeddingsModelName string = 'text-embedding-ada-002'

@description('Embeddings model version for the Azure AI Foundry deployment.')
param openAiEmbeddingsModelVersion string = '2'

@description('Throughput units for the Azure AI Foundry embeddings deployment.')
@minValue(1)
param openAiEmbeddingsDeploymentCapacity int = 10

@description('Embedding vector dimensions produced by the Azure AI Foundry embeddings deployment.')
@minValue(1)
param openAiEmbeddingsDimensions int = 1536

@description('Value used to force the index deployment script to rerun on each deployment.')
param searchIndexScriptForceUpdateTag string = newGuid()

@description('Value used to force the skillset deployment script to rerun on each deployment.')
param searchSkillsetScriptForceUpdateTag string = newGuid()

@description('Value used to force the indexer deployment script to rerun on each deployment.')
param searchIndexerScriptForceUpdateTag string = newGuid()

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
var searchSkillsetName = '${normalizedEnvironmentName}-index-and-vectorize-skillset'
var searchSkillsetModuleName = '${normalizedEnvironmentName}-skillset-script'
var searchIndexModuleName = '${normalizedEnvironmentName}-index-script'
var searchTargetIndexName = '${normalizedEnvironmentName}-index-and-vectorize'
var searchIndexerName = '${normalizedEnvironmentName}-index-and-vectorize-indexer'
var searchIndexerModuleName = '${normalizedEnvironmentName}-indexer-script'
var searchIndexChunkKeyFieldName = 'chunk_id'
var searchIndexParentKeyFieldName = 'parent_id'
var searchIndexChunkFieldName = 'chunk'
var searchIndexTitleFieldName = 'title'
var searchIndexVectorFieldName = 'text_vector'
var searchIndexSemanticConfigurationName = 'index-and-vectorize-semantic-configuration'
var searchIndexVectorAlgorithmName = 'index-and-vectorize-algorithm'
var searchIndexVectorProfileName = 'index-and-vectorize-azureOpenAi-text-profile'
var searchIndexVectorizerName = 'index-and-vectorize-azureOpenAi-text-vectorizer'
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
var openAiAccountModuleName = '${normalizedEnvironmentName}-aoai-deploy'
var openAiAccountBaseName = length(normalizedEnvironmentName) > 0 ? normalizedEnvironmentName : 'env'
var openAiAccountCandidate = '${openAiAccountBaseName}-aoai'
var openAiAccountName = length(openAiAccountCandidate) > 44 ? substring(openAiAccountCandidate, 0, 44) : openAiAccountCandidate
var openAiSubdomainBase = replace(openAiAccountBaseName, '-', '')
var openAiSubdomainBaseClean = length(openAiSubdomainBase) > 0 ? openAiSubdomainBase : 'aoai'
var openAiSubdomainWithSuffix = '${openAiSubdomainBaseClean}aoai'
var openAiCustomSubDomainName = length(openAiSubdomainWithSuffix) > 30 ? substring(openAiSubdomainWithSuffix, 0, 30) : openAiSubdomainWithSuffix
var openAiDeploymentName = openAiModelName
var openAiEmbeddingsDeploymentName = openAiEmbeddingsModelName
var openAiRoleAssignmentModuleName = '${normalizedEnvironmentName}-aoai-role'
var openAiContributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a001fd3d-188f-4b5d-821b-7da978bf7442')
var openAiContributorRoleAssignmentName = guid(subscription().id, finalResourceGroupName, openAiAccountName, searchServiceName, 'openai-contributor')
var appServicePlanName = '${normalizedEnvironmentName}-plan'
var webAppModuleName = '${normalizedEnvironmentName}-webapp-deploy'
var webAppBaseName = toLower(replace(replace(replace(resourceGroupName, '_', '-'), ' ', '-'), '--', '-'))
var webAppBaseFallback = length(webAppBaseName) == 0 ? '${normalizedEnvironmentName}-app' : webAppBaseName
var webAppNameCandidate = startsWith(webAppBaseFallback, '-') ? 'a${webAppBaseFallback}' : webAppBaseFallback
var webAppName = length(webAppNameCandidate) > 60 ? substring(webAppNameCandidate, 0, 60) : webAppNameCandidate

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

module openAi './azureOpenAi.bicep' = {
  name: openAiAccountModuleName
  scope: rg
  params: {
    openAiAccountName: openAiAccountName
    customSubDomainName: openAiCustomSubDomainName
    location: location
    tags: {
      'azd-env-name': environmentName
    }
    deploymentName: openAiDeploymentName
    modelName: openAiModelName
    modelVersion: openAiModelVersion
    capacity: openAiDeploymentCapacity
    embeddingsDeploymentName: openAiEmbeddingsDeploymentName
    embeddingsModelName: openAiEmbeddingsModelName
    embeddingsModelVersion: openAiEmbeddingsModelVersion
    embeddingsCapacity: openAiEmbeddingsDeploymentCapacity
  }
}

module openAiAccess './openAiRoleAssignment.bicep' = {
  name: openAiRoleAssignmentModuleName
  scope: rg
  params: {
    roleAssignmentName: openAiContributorRoleAssignmentName
    openAiAccountName: openAiAccountName
    principalId: searchService.outputs.searchServicePrincipalId
    roleDefinitionId: openAiContributorRoleDefinitionId
  }
}

module webApp './webApp.bicep' = {
  name: webAppModuleName
  scope: rg
  params: {
    appServicePlanName: appServicePlanName
    webAppName: webAppName
    location: location
    tags: {
      'azd-env-name': environmentName
      'azd-service-name': 'mcp'
    }
    appServicePlanSkuName: appServicePlanSkuName
    appServicePlanSkuTier: appServicePlanSkuTier
    appServicePlanSkuCapacity: appServicePlanSkuCapacity
    pythonVersion: webAppPythonVersion
    startupCommand: webAppStartupCommand
    alwaysOn: webAppAlwaysOn
    appSettings: {
      AZURE_ENV_NAME: environmentName
      CLOUD_NAME: cloudName
      SEARCH_SERVICE_ENDPOINT: searchService.outputs.searchServiceEndpoint
      SEARCH_INDEX_NAME: searchTargetIndexName
      SEARCH_SERVICE_NAME: searchServiceName
      OPENAI_ACCOUNT_ENDPOINT: openAi.outputs.openAiAccountEndpoint
      OPENAI_EMBEDDINGS_DEPLOYMENT_NAME: openAi.outputs.openAiEmbeddingsDeploymentName
    }
  }
}

module webAppSearchDataReader './searchServiceRoleAssignment.bicep' = {
  name: '${normalizedEnvironmentName}-webapp-search-reader'
  scope: rg
  params: {
    roleAssignmentName: guid(subscription().id, finalResourceGroupName, searchServiceName, webAppName, 'search-data-reader')
    searchServiceName: searchServiceName
    principalId: webApp.outputs.webAppIdentityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '1407120a-92aa-4202-b7e9-c0e197c71c8f')
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

module createSearchIndex './createSearchIndex.bicep' = {
  name: searchIndexModuleName
  scope: rg
  params: {
    location: location
    searchServiceName: searchServiceName
    indexName: searchTargetIndexName
    searchServiceEndpoint: searchService.outputs.searchServiceEndpoint
    resourceGroupName: finalResourceGroupName
    userAssignedIdentityResourceId: userAssignedIdentity.outputs.userAssignedIdentityId
    userAssignedIdentityClientId: userAssignedIdentity.outputs.userAssignedIdentityClientId
    cloudName: cloudName
    subscriptionId: subscription().subscriptionId
    tenantId: subscription().tenantId
    vectorDimensions: openAiEmbeddingsDimensions
    vectorFieldName: searchIndexVectorFieldName
    chunkFieldName: searchIndexChunkFieldName
    titleFieldName: searchIndexTitleFieldName
    chunkKeyFieldName: searchIndexChunkKeyFieldName
    parentKeyFieldName: searchIndexParentKeyFieldName
    semanticConfigurationName: searchIndexSemanticConfigurationName
    vectorSearchAlgorithmName: searchIndexVectorAlgorithmName
    vectorSearchProfileName: searchIndexVectorProfileName
    vectorSearchVectorizerName: searchIndexVectorizerName
    openAiResourceUri: openAi.outputs.openAiAccountEndpoint
    openAiDeploymentId: openAi.outputs.openAiEmbeddingsDeploymentName
    openAiModelName: openAi.outputs.openAiEmbeddingsDeploymentModel
    forceUpdateTag: searchIndexScriptForceUpdateTag
  }
  dependsOn: [
    scriptIdentitySearchContributor
    openAiAccess
  ]
}

module createSearchSkillset './createSkillset.bicep' = {
  name: searchSkillsetModuleName
  scope: rg
  params: {
    location: location
    searchServiceName: searchServiceName
    skillsetName: searchSkillsetName
    searchServiceEndpoint: searchService.outputs.searchServiceEndpoint
    resourceGroupName: finalResourceGroupName
    userAssignedIdentityResourceId: userAssignedIdentity.outputs.userAssignedIdentityId
    userAssignedIdentityClientId: userAssignedIdentity.outputs.userAssignedIdentityClientId
    cloudName: cloudName
    subscriptionId: subscription().subscriptionId
    tenantId: subscription().tenantId
    openAiResourceUri: openAi.outputs.openAiAccountEndpoint
    openAiDeploymentId: openAi.outputs.openAiEmbeddingsDeploymentName
    openAiModelName: openAi.outputs.openAiEmbeddingsDeploymentModel
    openAiEmbeddingDimensions: openAiEmbeddingsDimensions
    targetIndexName: searchTargetIndexName
    parentKeyFieldName: searchIndexParentKeyFieldName
    vectorFieldName: searchIndexVectorFieldName
    chunkFieldName: searchIndexChunkFieldName
    titleFieldName: searchIndexTitleFieldName
    forceUpdateTag: searchSkillsetScriptForceUpdateTag
  }
  dependsOn: [
    scriptIdentitySearchContributor
    createSearchDataSource
    openAiAccess
    createSearchIndex
  ]
}

module createSearchIndexer './createSearchIndexer.bicep' = {
  name: searchIndexerModuleName
  scope: rg
  params: {
    location: location
    searchServiceName: searchServiceName
    indexerName: searchIndexerName
    dataSourceName: searchDataSourceName
    skillsetName: searchSkillsetName
    targetIndexName: searchTargetIndexName
    searchServiceEndpoint: searchService.outputs.searchServiceEndpoint
    resourceGroupName: finalResourceGroupName
    userAssignedIdentityResourceId: userAssignedIdentity.outputs.userAssignedIdentityId
    userAssignedIdentityClientId: userAssignedIdentity.outputs.userAssignedIdentityClientId
    cloudName: cloudName
    subscriptionId: subscription().subscriptionId
    tenantId: subscription().tenantId
    parsingMode: 'default'
    titleSourceFieldName: 'metadata_storage_name'
    titleTargetFieldName: searchIndexTitleFieldName
    forceUpdateTag: searchIndexerScriptForceUpdateTag
  }
  dependsOn: [
    scriptIdentitySearchContributor
    createSearchDataSource
    createSearchIndex
    createSearchSkillset
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
output OPENAI_ACCOUNT_ID string = openAi.outputs.openAiAccountId
output OPENAI_ACCOUNT_NAME string = openAi.outputs.openAiAccountName
output OPENAI_ACCOUNT_ENDPOINT string = openAi.outputs.openAiAccountEndpoint
output OPENAI_DEPLOYMENT_ID string = openAi.outputs.openAiDeploymentId
output OPENAI_DEPLOYMENT_NAME string = openAi.outputs.openAiDeploymentName
output OPENAI_DEPLOYMENT_MODEL string = openAi.outputs.openAiDeploymentModel
output OPENAI_EMBEDDINGS_DEPLOYMENT_ID string = openAi.outputs.openAiEmbeddingsDeploymentId
output OPENAI_EMBEDDINGS_DEPLOYMENT_NAME string = openAi.outputs.openAiEmbeddingsDeploymentName
output OPENAI_EMBEDDINGS_DEPLOYMENT_MODEL string = openAi.outputs.openAiEmbeddingsDeploymentModel
output STORAGE_ACCOUNT_ID string = storageAccount.outputs.storageAccountId
output STORAGE_ACCOUNT_NAME string = storageAccountName
output STORAGE_ACCOUNT_BLOB_ENDPOINT string = storageAccount.outputs.blobEndpoint
output STORAGE_ACCOUNT_TABLE_ENDPOINT string = storageAccount.outputs.tableEndpoint
output STORAGE_ACCOUNT_QUEUE_ENDPOINT string = storageAccount.outputs.queueEndpoint
output STORAGE_ACCOUNT_FILE_ENDPOINT string = storageAccount.outputs.fileEndpoint
output STORAGE_ACCOUNT_CONTAINER_NAME string = storageContainerName
output SEARCH_DATA_SOURCE_NAME string = searchDataSourceName
output SEARCH_INDEX_NAME string = searchTargetIndexName
output WEB_APP_ID string = webApp.outputs.webAppId
output WEB_APP_NAME string = webAppName
output WEB_APP_DEFAULT_HOST_NAME string = webApp.outputs.webAppDefaultHostName
output WEB_APP_MANAGED_IDENTITY_PRINCIPAL_ID string = webApp.outputs.webAppIdentityPrincipalId
output AZURE_MCP_WEBAPP_NAME string = webAppName
output AZURE_MCP_WEBAPP_RESOURCE_ID string = webApp.outputs.webAppId
