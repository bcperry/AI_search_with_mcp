targetScope = 'resourceGroup'

@description('Azure region for the deployment script execution.')
param location string

@description('Name of the Azure AI Search service.')
param searchServiceName string

@description('Name of the indexer to upsert.')
param indexerName string

@description('Name of the data source that feeds the indexer.')
param dataSourceName string

@description('Name of the skillset executed by the indexer.')
param skillsetName string

@description('Name of the target index populated by the indexer.')
param targetIndexName string

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

@description('Parsing mode configuration for the indexer.')
param parsingMode string = 'default'

@description('Name of the source field used for title mapping.')
param titleSourceFieldName string = 'metadata_storage_name'

@description('Name of the target title field in the index.')
param titleTargetFieldName string = 'title'

@description('Value used to force redeployment of the script when changed.')
param forceUpdateTag string

var scriptName = '${uniqueString(resourceGroup().id, searchServiceName, indexerName)}-createindexer'

resource createIndexer 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
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
    forceUpdateTag: forceUpdateTag
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
        name: 'INDEXER_NAME'
        value: indexerName
      }
      {
        name: 'DATA_SOURCE_NAME'
        value: dataSourceName
      }
      {
        name: 'SKILLSET_NAME'
        value: skillsetName
      }
      {
        name: 'TARGET_INDEX_NAME'
        value: targetIndexName
      }
      {
        name: 'PARSING_MODE'
        value: parsingMode
      }
      {
        name: 'TITLE_SOURCE_FIELD_NAME'
        value: titleSourceFieldName
      }
      {
        name: 'TITLE_TARGET_FIELD_NAME'
        value: titleTargetFieldName
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

API_VERSION="2024-09-01-preview"
ADMIN_KEY=$(az search admin-key show --resource-group "$RESOURCE_GROUP_NAME" --service-name "$SEARCH_SERVICE_NAME" --query primaryKey -o tsv)

if [[ -z "$ADMIN_KEY" ]]; then
  echo "Failed to retrieve search admin key" >&2
  exit 1
fi

PAYLOAD_FILE=$(mktemp)
trap 'rm -f "$PAYLOAD_FILE"' EXIT

cat <<EOF >"$PAYLOAD_FILE"
{
  "name": "$INDEXER_NAME",
  "dataSourceName": "$DATA_SOURCE_NAME",
  "skillsetName": "$SKILLSET_NAME",
  "targetIndexName": "$TARGET_INDEX_NAME",
  "parameters": {
    "configuration": {
      "parsingMode": "$PARSING_MODE"
    }
  },
  "fieldMappings": [
    {
      "sourceFieldName": "$TITLE_SOURCE_FIELD_NAME",
      "targetFieldName": "$TITLE_TARGET_FIELD_NAME"
    }
  ]
}
EOF

az rest --method put \
  --uri "$SEARCH_SERVICE_ENDPOINT/indexers('$INDEXER_NAME')" \
  --url-parameters "api-version=$API_VERSION" \
  --headers "Content-Type=application/json" "api-key=$ADMIN_KEY" \
  --skip-authorization-header \
  --body @"$PAYLOAD_FILE"
'''
  }
}

output deploymentScriptName string = createIndexer.name
