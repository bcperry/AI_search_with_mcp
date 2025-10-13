targetScope = 'resourceGroup'

@description('Azure region for the deployment script execution.')
param location string

@description('Name of the Azure AI Search service.')
param searchServiceName string

@description('Name of the search index to upsert.')
param indexName string

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

@description('Embedding vector dimensions for the vector field.')
@minValue(1)
param vectorDimensions int = 1536

@description('Name of the vector field.')
param vectorFieldName string = 'text_vector'

@description('Name of the text chunk field.')
param chunkFieldName string = 'chunk'

@description('Name of the title field.')
param titleFieldName string = 'title'

@description('Name of the chunk key field.')
param chunkKeyFieldName string = 'chunk_id'

@description('Name of the parent key field.')
param parentKeyFieldName string = 'parent_id'

@description('Name of the semantic configuration applied to the index.')
param semanticConfigurationName string = 'index-and-vectorize-semantic-configuration'

@description('Name of the vector search algorithm definition.')
param vectorSearchAlgorithmName string = 'index-and-vectorize-algorithm'

@description('Name of the vector search profile applied to the vector field.')
param vectorSearchProfileName string = 'index-and-vectorize-azureOpenAi-text-profile'

@description('Name of the Azure OpenAI vectorizer configuration.')
param vectorSearchVectorizerName string = 'index-and-vectorize-azureOpenAi-text-vectorizer'

@description('Azure OpenAI resource URI used by the vectorizer (e.g. https://foo.openai.azure.com).')
param openAiResourceUri string

@description('Azure OpenAI deployment identifier used by the vectorizer.')
param openAiDeploymentId string

@description('Azure OpenAI model name used by the vectorizer.')
param openAiModelName string

@description('Value used to force redeployment of the script when changed.')
param forceUpdateTag string

var scriptName = '${uniqueString(resourceGroup().id, searchServiceName, indexName)}-createindex'

resource createIndex 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
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
        name: 'INDEX_NAME'
        value: indexName
      }
      {
        name: 'CHUNK_KEY_FIELD_NAME'
        value: chunkKeyFieldName
      }
      {
        name: 'PARENT_KEY_FIELD_NAME'
        value: parentKeyFieldName
      }
      {
        name: 'CHUNK_FIELD_NAME'
        value: chunkFieldName
      }
      {
        name: 'TITLE_FIELD_NAME'
        value: titleFieldName
      }
      {
        name: 'VECTOR_FIELD_NAME'
        value: vectorFieldName
      }
      {
        name: 'VECTOR_DIMENSIONS'
        value: string(vectorDimensions)
      }
      {
        name: 'SEMANTIC_CONFIGURATION_NAME'
        value: semanticConfigurationName
      }
      {
        name: 'VECTOR_SEARCH_ALGORITHM_NAME'
        value: vectorSearchAlgorithmName
      }
      {
        name: 'VECTOR_SEARCH_PROFILE_NAME'
        value: vectorSearchProfileName
      }
      {
        name: 'VECTOR_SEARCH_VECTORIZER_NAME'
        value: vectorSearchVectorizerName
      }
      {
        name: 'OPENAI_RESOURCE_URI'
        value: openAiResourceUri
      }
      {
        name: 'OPENAI_DEPLOYMENT_ID'
        value: openAiDeploymentId
      }
      {
        name: 'OPENAI_MODEL_NAME'
        value: openAiModelName
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

OPENAI_RESOURCE_URI=${OPENAI_RESOURCE_URI%/}
PAYLOAD_FILE=$(mktemp)
trap 'rm -f "$PAYLOAD_FILE"' EXIT

cat <<EOF >"$PAYLOAD_FILE"
{
  "name": "$INDEX_NAME",
  "fields": [
    {
      "name": "$CHUNK_KEY_FIELD_NAME",
      "type": "Edm.String",
      "searchable": true,
      "filterable": false,
      "retrievable": true,
      "stored": true,
      "sortable": true,
      "facetable": false,
      "key": true,
      "analyzer": "keyword",
      "synonymMaps": []
    },
    {
      "name": "$PARENT_KEY_FIELD_NAME",
      "type": "Edm.String",
      "searchable": false,
      "filterable": true,
      "retrievable": true,
      "stored": true,
      "sortable": false,
      "facetable": false,
      "key": false,
      "synonymMaps": []
    },
    {
      "name": "$CHUNK_FIELD_NAME",
      "type": "Edm.String",
      "searchable": true,
      "filterable": false,
      "retrievable": true,
      "stored": true,
      "sortable": false,
      "facetable": false,
      "key": false,
      "synonymMaps": []
    },
    {
      "name": "$TITLE_FIELD_NAME",
      "type": "Edm.String",
      "searchable": true,
      "filterable": false,
      "retrievable": true,
      "stored": true,
      "sortable": false,
      "facetable": false,
      "key": false,
      "synonymMaps": []
    },
    {
      "name": "$VECTOR_FIELD_NAME",
      "type": "Collection(Edm.Single)",
      "searchable": true,
      "filterable": false,
      "retrievable": true,
      "stored": true,
      "sortable": false,
      "facetable": false,
      "key": false,
      "dimensions": $VECTOR_DIMENSIONS,
      "vectorSearchProfile": "$VECTOR_SEARCH_PROFILE_NAME",
      "synonymMaps": []
    }
  ],
  "scoringProfiles": [],
  "suggesters": [],
  "analyzers": [],
  "normalizers": [],
  "tokenizers": [],
  "tokenFilters": [],
  "charFilters": [],
  "similarity": {
    "@odata.type": "#Microsoft.Azure.Search.BM25Similarity"
  },
  "semantic": {
    "defaultConfiguration": "$SEMANTIC_CONFIGURATION_NAME",
    "configurations": [
      {
        "name": "$SEMANTIC_CONFIGURATION_NAME",
        "prioritizedFields": {
          "titleField": {
            "fieldName": "$TITLE_FIELD_NAME"
          },
          "prioritizedContentFields": [
            {
              "fieldName": "$CHUNK_FIELD_NAME"
            }
          ],
          "prioritizedKeywordsFields": []
        }
      }
    ]
  },
  "vectorSearch": {
    "algorithms": [
      {
        "name": "$VECTOR_SEARCH_ALGORITHM_NAME",
        "kind": "hnsw",
        "hnswParameters": {
          "metric": "cosine",
          "m": 4,
          "efConstruction": 400,
          "efSearch": 500
        }
      }
    ],
    "profiles": [
      {
        "name": "$VECTOR_SEARCH_PROFILE_NAME",
        "algorithm": "$VECTOR_SEARCH_ALGORITHM_NAME",
        "vectorizer": "$VECTOR_SEARCH_VECTORIZER_NAME"
      }
    ],
    "vectorizers": [
      {
        "name": "$VECTOR_SEARCH_VECTORIZER_NAME",
        "kind": "azureOpenAI",
        "azureOpenAIParameters": {
          "resourceUri": "$OPENAI_RESOURCE_URI",
          "deploymentId": "$OPENAI_DEPLOYMENT_ID",
          "modelName": "$OPENAI_MODEL_NAME"
        }
      }
    ],
    "compressions": []
  }
}
EOF

az rest --method put \
  --uri "$SEARCH_SERVICE_ENDPOINT/indexes('$INDEX_NAME')" \
  --url-parameters "api-version=$API_VERSION" \
  --headers "Content-Type=application/json" "api-key=$ADMIN_KEY" \
  --skip-authorization-header \
  --body @"$PAYLOAD_FILE"
'''
  }
}

output deploymentScriptName string = createIndex.name
