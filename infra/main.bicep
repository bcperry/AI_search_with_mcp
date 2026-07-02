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

@description('Name of an existing Azure AI Search service to reuse. Leave empty for first-time provisioning.')
param existingSearchServiceName string = ''

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

@description('Embeddings model identifier to deploy to Azure AI Foundry.')
param openAiEmbeddingsModelName string = 'text-embedding-ada-002'

@description('Name of an existing Azure AI Foundry (Azure OpenAI) account to reuse. Leave empty for first-time provisioning.')
param existingOpenAiAccountName string = ''

@description('Name of an existing Azure OpenAI embeddings deployment to reuse. Leave empty for first-time provisioning.')
param existingOpenAiEmbeddingsDeploymentName string = ''

@description('Embeddings model version for the Azure AI Foundry deployment.')
param openAiEmbeddingsModelVersion string = '2'

@description('Throughput units for the Azure AI Foundry embeddings deployment.')
@minValue(1)
param openAiEmbeddingsDeploymentCapacity int = 10

@description('Embedding vector dimensions produced by the Azure AI Foundry embeddings deployment.')
@minValue(1)
param openAiEmbeddingsDimensions int = 1536

@description('SKU name for the Azure AI Document Intelligence account used for layout/table extraction.')
@allowed([
  'F0'
  'S0'
])
param documentIntelligenceSkuName string = 'S0'

@description('Enable Azure AD token validation on the MCP server (true/false).')
param azureAdRequireAuth string = 'false'

@description('Azure AD tenant ID for MCP server token validation.')
param azureAdTenantId string = ''

@description('Azure AD app registration client ID for MCP server token validation (expected audience).')
param azureAdClientId string = ''

var normalizedEnvironmentName = toLower(replace(environmentName, ' ', '-'))
var finalResourceGroupName = resourceGroupName
var searchServiceName = '${normalizedEnvironmentName}-search'
var searchServiceModuleName = '${normalizedEnvironmentName}-search-deploy'
var useExistingSearchService = !empty(existingSearchServiceName)
var resolvedSearchServiceName = useExistingSearchService ? existingSearchServiceName : searchServiceName
var storageAccountModuleName = '${normalizedEnvironmentName}-storage-deploy'
var storageContainerName = 'aisearchdata'
var searchTargetIndexName = '${normalizedEnvironmentName}-index-and-vectorize'
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
var provisionedOpenAiAccountName = length(openAiAccountCandidate) > 44 ? substring(openAiAccountCandidate, 0, 44) : openAiAccountCandidate
var useExistingOpenAi = !empty(existingOpenAiAccountName) && !empty(existingOpenAiEmbeddingsDeploymentName)
var resolvedOpenAiAccountName = useExistingOpenAi ? existingOpenAiAccountName : provisionedOpenAiAccountName
var openAiSubdomainBase = replace(openAiAccountBaseName, '-', '')
var openAiSubdomainBaseClean = length(openAiSubdomainBase) > 0 ? openAiSubdomainBase : 'aoai'
var openAiSubdomainWithSuffix = '${openAiSubdomainBaseClean}aoai'
var openAiCustomSubDomainName = length(openAiSubdomainWithSuffix) > 30 ? substring(openAiSubdomainWithSuffix, 0, 30) : openAiSubdomainWithSuffix
var provisionedOpenAiEmbeddingsDeploymentName = openAiEmbeddingsModelName
var openAiRoleAssignmentModuleName = '${normalizedEnvironmentName}-aoai-role'
var openAiContributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a001fd3d-188f-4b5d-821b-7da978bf7442')
var openAiContributorRoleAssignmentName = guid(subscription().id, finalResourceGroupName, resolvedOpenAiAccountName, resolvedSearchServiceName, 'openai-contributor')
var documentIntelligenceModuleName = '${normalizedEnvironmentName}-di-deploy'
var documentIntelligenceAccountCandidate = '${openAiSubdomainBaseClean}di'
var documentIntelligenceAccountName = length(documentIntelligenceAccountCandidate) > 30 ? substring(documentIntelligenceAccountCandidate, 0, 30) : documentIntelligenceAccountCandidate
var appServicePlanName = '${normalizedEnvironmentName}-plan'
var webAppModuleName = '${normalizedEnvironmentName}-webapp-deploy'
var webAppBaseName = toLower(replace(replace(replace(resourceGroupName, '_', '-'), ' ', '-'), '--', '-'))
var webAppBaseFallback = length(webAppBaseName) == 0 ? '${normalizedEnvironmentName}-app' : webAppBaseName
var webAppNameCandidate = startsWith(webAppBaseFallback, '-') ? 'a${webAppBaseFallback}' : webAppBaseFallback
var webAppName = length(webAppNameCandidate) > 60 ? substring(webAppNameCandidate, 0, 60) : webAppNameCandidate
var logAnalyticsModuleName = '${normalizedEnvironmentName}-logs-deploy'
var logAnalyticsWorkspaceName = '${normalizedEnvironmentName}-logs'

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: finalResourceGroupName
  location: location
  tags: {
    'azd-env-name': environmentName
  }
}

module searchService 'searchService.bicep' = if (!useExistingSearchService) {
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

module existingSearchService './searchServiceExisting.bicep' = if (useExistingSearchService) {
  name: '${normalizedEnvironmentName}-search-existing'
  scope: rg
  params: {
    searchServiceName: existingSearchServiceName
    endpointSuffix: resolvedSearchEndpointSuffix
  }
}

var searchServiceId = useExistingSearchService ? existingSearchService!.outputs.searchServiceId : searchService!.outputs.searchServiceId
var searchServiceEndpoint = useExistingSearchService ? existingSearchService!.outputs.searchServiceEndpoint : searchService!.outputs.searchServiceEndpoint
var searchServicePrincipalId = useExistingSearchService ? existingSearchService!.outputs.searchServicePrincipalId : searchService!.outputs.searchServicePrincipalId

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

module openAi './azureOpenAi.bicep' = if (!useExistingOpenAi) {
  name: openAiAccountModuleName
  scope: rg
  params: {
    openAiAccountName: provisionedOpenAiAccountName
    customSubDomainName: openAiCustomSubDomainName
    location: location
    tags: {
      'azd-env-name': environmentName
    }
    embeddingsDeploymentName: provisionedOpenAiEmbeddingsDeploymentName
    embeddingsModelName: openAiEmbeddingsModelName
    embeddingsModelVersion: openAiEmbeddingsModelVersion
    embeddingsCapacity: openAiEmbeddingsDeploymentCapacity
  }
}

module existingOpenAi './azureOpenAiExisting.bicep' = if (useExistingOpenAi) {
  name: '${normalizedEnvironmentName}-aoai-existing'
  scope: rg
  params: {
    openAiAccountName: existingOpenAiAccountName
    embeddingsDeploymentName: existingOpenAiEmbeddingsDeploymentName
  }
}

var openAiAccountId = useExistingOpenAi ? existingOpenAi!.outputs.openAiAccountId : openAi!.outputs.openAiAccountId
var openAiAccountEndpoint = useExistingOpenAi ? existingOpenAi!.outputs.openAiAccountEndpoint : openAi!.outputs.openAiAccountEndpoint
var openAiEmbeddingsDeploymentId = useExistingOpenAi ? existingOpenAi!.outputs.openAiEmbeddingsDeploymentId : openAi!.outputs.openAiEmbeddingsDeploymentId
var openAiEmbeddingsDeploymentName = useExistingOpenAi ? existingOpenAi!.outputs.openAiEmbeddingsDeploymentName : openAi!.outputs.openAiEmbeddingsDeploymentName
var openAiEmbeddingsDeploymentModel = useExistingOpenAi ? existingOpenAi!.outputs.openAiEmbeddingsDeploymentModel : openAi!.outputs.openAiEmbeddingsDeploymentModel

module openAiAccess './openAiRoleAssignment.bicep' = {
  name: openAiRoleAssignmentModuleName
  scope: rg
  params: {
    roleAssignmentName: openAiContributorRoleAssignmentName
    openAiAccountName: resolvedOpenAiAccountName
    principalId: searchServicePrincipalId
    roleDefinitionId: openAiContributorRoleDefinitionId
  }
}

module documentIntelligence './documentIntelligence.bicep' = {
  name: documentIntelligenceModuleName
  scope: rg
  params: {
    documentIntelligenceAccountName: documentIntelligenceAccountName
    location: location
    skuName: documentIntelligenceSkuName
    tags: {
      'azd-env-name': environmentName
    }
  }
}

module logAnalytics './logAnalytics.bicep' = {
  name: logAnalyticsModuleName
  scope: rg
  params: {
    workspaceName: logAnalyticsWorkspaceName
    location: location
    tags: {
      'azd-env-name': environmentName
    }
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
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    appSettings: {
      AZURE_ENV_NAME: environmentName
      CLOUD_NAME: cloudName
      SEARCH_SERVICE_ENDPOINT: searchServiceEndpoint
      SEARCH_INDEX_NAME: searchTargetIndexName
      SEARCH_SERVICE_NAME: resolvedSearchServiceName
      OPENAI_ACCOUNT_ENDPOINT: openAiAccountEndpoint
      OPENAI_EMBEDDINGS_DEPLOYMENT_NAME: openAiEmbeddingsDeploymentName
      DOCUMENT_INTELLIGENCE_ACCOUNT_NAME: documentIntelligence.outputs.documentIntelligenceAccountName
      DOCUMENT_INTELLIGENCE_ENDPOINT: documentIntelligence.outputs.documentIntelligenceEndpoint
      STORAGE_ACCOUNT_BLOB_ENDPOINT: storageAccount.outputs.blobEndpoint
      STORAGE_ACCOUNT_CONTAINER_NAME: storageContainerName
      AZURE_AD_REQUIRE_AUTH: azureAdRequireAuth
      AZURE_AD_TENANT_ID: azureAdTenantId
      AZURE_AD_CLIENT_ID: azureAdClientId
    }
  }
}

module webAppSearchDataReader './searchServiceRoleAssignment.bicep' = {
  name: '${normalizedEnvironmentName}-webapp-search-reader'
  scope: rg
  params: {
    roleAssignmentName: guid(subscription().id, finalResourceGroupName, resolvedSearchServiceName, webAppName, 'search-data-reader')
    searchServiceName: resolvedSearchServiceName
    principalId: webApp.outputs.webAppIdentityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '1407120a-92aa-4202-b7e9-c0e197c71c8f')
  }
}

module webAppSearchServiceContributor './searchServiceRoleAssignment.bicep' = {
  name: '${normalizedEnvironmentName}-webapp-search-contrib'
  scope: rg
  params: {
    roleAssignmentName: guid(subscription().id, finalResourceGroupName, resolvedSearchServiceName, webAppName, 'search-service-contributor')
    searchServiceName: resolvedSearchServiceName
    principalId: webApp.outputs.webAppIdentityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
  }
}

module searchServiceBlobDataReader 'storageAccountRoleAssignment.bicep' = {
  name: '${normalizedEnvironmentName}-search-blob-reader'
  scope: rg
  params: {
    roleAssignmentName: guid(subscription().id, finalResourceGroupName, storageAccountName, resolvedSearchServiceName, 'blob-data-reader')
    storageAccountName: storageAccountName
    principalId: searchServicePrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
  }
}

module webAppBlobDataReader 'storageAccountRoleAssignment.bicep' = {
  name: '${normalizedEnvironmentName}-webapp-blob-reader'
  scope: rg
  params: {
    roleAssignmentName: guid(subscription().id, finalResourceGroupName, storageAccountName, webAppName, 'blob-data-reader')
    storageAccountName: storageAccountName
    principalId: webApp.outputs.webAppIdentityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
  }
}

output RESOURCE_GROUP_ID string = rg.id
output REQUESTED_RESOURCE_GROUP_NAME string = resourceGroupName
output SEARCH_SERVICE_ID string = searchServiceId
output SEARCH_SERVICE_NAME string = resolvedSearchServiceName
output SEARCH_SERVICE_ENDPOINT string = searchServiceEndpoint
output SEARCH_SERVICE_ENDPOINT_SUFFIX string = resolvedSearchEndpointSuffix
output CLOUD_NAME string = cloudName
output OPENAI_ACCOUNT_ID string = openAiAccountId
output OPENAI_ACCOUNT_NAME string = resolvedOpenAiAccountName
output OPENAI_ACCOUNT_ENDPOINT string = openAiAccountEndpoint
output OPENAI_EMBEDDINGS_DEPLOYMENT_ID string = openAiEmbeddingsDeploymentId
output OPENAI_EMBEDDINGS_DEPLOYMENT_NAME string = openAiEmbeddingsDeploymentName
output OPENAI_EMBEDDINGS_DEPLOYMENT_MODEL string = openAiEmbeddingsDeploymentModel
output OPENAI_EMBEDDINGS_DIMENSIONS string = string(openAiEmbeddingsDimensions)
output DOCUMENT_INTELLIGENCE_ACCOUNT_ID string = documentIntelligence.outputs.documentIntelligenceAccountId
output DOCUMENT_INTELLIGENCE_ACCOUNT_NAME string = documentIntelligence.outputs.documentIntelligenceAccountName
output DOCUMENT_INTELLIGENCE_ENDPOINT string = documentIntelligence.outputs.documentIntelligenceEndpoint
output STORAGE_ACCOUNT_ID string = storageAccount.outputs.storageAccountId
output STORAGE_ACCOUNT_NAME string = storageAccountName
output STORAGE_ACCOUNT_BLOB_ENDPOINT string = storageAccount.outputs.blobEndpoint
output STORAGE_ACCOUNT_TABLE_ENDPOINT string = storageAccount.outputs.tableEndpoint
output STORAGE_ACCOUNT_QUEUE_ENDPOINT string = storageAccount.outputs.queueEndpoint
output STORAGE_ACCOUNT_FILE_ENDPOINT string = storageAccount.outputs.fileEndpoint
output STORAGE_ACCOUNT_CONTAINER_NAME string = storageContainerName
output SEARCH_INDEX_NAME string = searchTargetIndexName
output SEARCH_TABLE_ROW_INDEX_NAME string = '${normalizedEnvironmentName}-table-rows'
output WEB_APP_ID string = webApp.outputs.webAppId
output WEB_APP_NAME string = webAppName
output WEB_APP_DEFAULT_HOST_NAME string = webApp.outputs.webAppDefaultHostName
output WEB_APP_MANAGED_IDENTITY_PRINCIPAL_ID string = webApp.outputs.webAppIdentityPrincipalId
output AZURE_MCP_WEBAPP_NAME string = webAppName
output AZURE_MCP_WEBAPP_RESOURCE_ID string = webApp.outputs.webAppId
