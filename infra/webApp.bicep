targetScope = 'resourceGroup'

@description('Name of the App Service plan to create.')
param appServicePlanName string

@description('Name of the Web App to create. Must be globally unique within the Azure App Service domain.')
param webAppName string

@description('Azure region for the App Service resources.')
param location string

@description('Tags to apply to created resources.')
param tags object = {}

@description('SKU name for the App Service plan (for example, P1v3, S1, B1).')
param appServicePlanSkuName string

@description('SKU tier for the App Service plan (for example, PremiumV3, Standard, Basic).')
param appServicePlanSkuTier string

@description('Number of workers to provision for the App Service plan.')
@minValue(1)
param appServicePlanSkuCapacity int = 1

@description('Python runtime version for the Web App.')
param pythonVersion string = '3.10'

@description('Startup command executed by the Web App.')
param startupCommand string = 'python main.py'

@description('Whether Always On should be enabled for the Web App.')
param alwaysOn bool = true

@description('Additional application settings to apply to the Web App.')
param appSettings object = {}

var defaultAppSettings = {
  SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
  ENABLE_ORYX_BUILD: 'true'
  WEBSITES_PORT: '8000'
}

var mergedAppSettings = union(defaultAppSettings, appSettings)

// Remove azd-service-name from the App Service Plan tags to avoid duplicate service detection
var planTags = filter(items(tags), item => item.key != 'azd-service-name')
var planTagsObject = toObject(planTags, item => item.key, item => item.value)

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: appServicePlanSkuName
    tier: appServicePlanSkuTier
    size: appServicePlanSkuName
    capacity: appServicePlanSkuCapacity
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
  tags: planTagsObject
}

resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: webAppName
  location: location
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'PYTHON|${pythonVersion}'
      alwaysOn: alwaysOn
      appCommandLine: startupCommand
      ftpsState: 'Disabled'
      appSettings: [
        for setting in items(mergedAppSettings): {
          name: setting.key
          value: string(setting.value)
        }
      ]
    }
  }
  tags: tags
}

output appServicePlanId string = appServicePlan.id
output webAppId string = webApp.id
output webAppDefaultHostName string = webApp.properties.defaultHostName
output webAppIdentityPrincipalId string = webApp.identity.principalId
