targetScope = 'resourceGroup'

@description('Azure region for the deployment script execution.')
param location string

@description('Name of the Azure AI Search service.')
param searchServiceName string

@description('Data source name to upsert.')
param dataSourceName string

@description('Blob container name backing the data source.')
param containerName string

@description('Storage account resource ID referenced by the data source connection string.')
param storageAccountResourceId string

@description('Fully qualified endpoint for the search service (e.g. https://foo.search.windows.net).')
param searchServiceEndpoint string

@description('Resource group name hosting the search service.')
param resourceGroupName string

@description('Resource ID of the user-assigned managed identity to execute the deployment script.')
param userAssignedIdentityResourceId string

@description('Client ID of the user-assigned managed identity to execute the deployment script.')
param userAssignedIdentityClientId string

@description('Azure cloud name (e.g. AzureCloud, AzureUSGovernment).')
param cloudName string

@description('Azure subscription ID for authentication context.')
param subscriptionId string

@description('Azure tenant ID for authentication context.')
param tenantId string

var scriptName = '${uniqueString(resourceGroup().id, searchServiceName, dataSourceName)}-createds'

resource createDataSource 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: scriptName
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityResourceId}': {}
    }
  }
  properties: {
    azCliVersion: '2.56.0'
    timeout: 'PT15M'
    retentionInterval: 'P1D'
    cleanupPreference: 'OnSuccess'
    environmentVariables: [
      {
        name: 'RESOURCE_GROUP_NAME'
        value: resourceGroupName
      }
      {
        name: 'SEARCH_SERVICE_NAME'
        value: searchServiceName
      }
      {
        name: 'SEARCH_SERVICE_ENDPOINT'
        value: searchServiceEndpoint
      }
      {
        name: 'DATA_SOURCE_NAME'
        value: dataSourceName
      }
      {
        name: 'STORAGE_ACCOUNT_RESOURCE_ID'
        value: storageAccountResourceId
      }
      {
        name: 'CONTAINER_NAME'
        value: containerName
      }
      {
        name: 'USER_ASSIGNED_IDENTITY_CLIENT_ID'
        value: userAssignedIdentityClientId
      }
      {
        name: 'CLOUD_NAME'
        value: cloudName
      }
      {
        name: 'AZURE_SUBSCRIPTION_ID'
        value: subscriptionId
      }
      {
        name: 'AZURE_TENANT_ID'
        value: tenantId
      }
    ]
    scriptContent: '''#!/bin/bash
set -euo pipefail

if [[ -n "${CLOUD_NAME:-}" ]]; then
  az cloud set --name "$CLOUD_NAME" >/dev/null
fi

az login --identity --username "$USER_ASSIGNED_IDENTITY_CLIENT_ID" >/dev/null

if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
  az account set --subscription "$AZURE_SUBSCRIPTION_ID" >/dev/null
fi

    API_VERSION="2020-06-30"
ADMIN_KEY=$(az search admin-key show --resource-group "$RESOURCE_GROUP_NAME" --service-name "$SEARCH_SERVICE_NAME" --query primaryKey -o tsv)

if [[ -z "$ADMIN_KEY" ]]; then
  echo "Failed to retrieve search admin key" >&2
  exit 1
fi

CONNECTION_STRING="ResourceId=$STORAGE_ACCOUNT_RESOURCE_ID"
PAYLOAD_FILE=$(mktemp)
trap 'rm -f "$PAYLOAD_FILE"' EXIT

cat <<EOF >"$PAYLOAD_FILE"
{
  "name": "$DATA_SOURCE_NAME",
  "type": "azureblob",
  "credentials": {
    "connectionString": "$CONNECTION_STRING"
  },
  "container": {
    "name": "$CONTAINER_NAME"
  }
}
EOF

az rest --method put \
  --uri "$SEARCH_SERVICE_ENDPOINT/datasources/$DATA_SOURCE_NAME" \
  --url-parameters "api-version=$API_VERSION" \
  --headers "Content-Type=application/json" "api-key=$ADMIN_KEY" \
  --skip-authorization-header \
  --body @"$PAYLOAD_FILE"
'''
  }
}

output deploymentScriptName string = createDataSource.name
