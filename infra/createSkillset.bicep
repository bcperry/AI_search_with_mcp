targetScope = 'resourceGroup'

@description('Azure region for the deployment script execution.')
param location string

@description('Name of the Azure AI Search service.')
param searchServiceName string

@description('Name of the skillset to upsert.')
param skillsetName string

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

@description('Description to assign to the skillset.')
param skillsetDescription string = 'Skillset to chunk documents and generate embeddings'

@description('Default language code for the split skill.')
param defaultLanguageCode string = 'en'

@description('Mode to use for the split skill (e.g. pages, sentences).')
param textSplitMode string = 'pages'

@description('Maximum number of characters per chunk for the split skill.')
@minValue(1)
param maximumPageLength int = 2000

@description('Number of characters overlapping between sequential chunks.')
@minValue(0)
param pageOverlapLength int = 500

@description('Maximum number of pages to take (0 for all).')
@minValue(0)
param maximumPagesToTake int = 0

@description('Unit to use for the split skill (e.g. characters, sentences).')
param splitUnit string = 'characters'

@description('Path to the document content used as input for chunking.')
param documentContentSourcePath string = '/document/content'

@description('Root context for the document content.')
param documentContext string = '/document'

@description('Context path for page-level content.')
param pageSourceContext string = '/document/pages/*'

@description('Path to the document title field.')
param titleSourcePath string = '/document/title'

@description('Path to the source blob URI field.')
param sourcePathSourcePath string = '/document/metadata_storage_path'

@description('Name assigned to the split skill within the skillset.')
param splitSkillName string = 'splitSkill'

@description('Name assigned to the embedding skill within the skillset.')
param embeddingSkillName string = 'embeddingSkill'

@description('Output target name produced by the split skill.')
param splitSkillOutputTargetName string = 'pages'

@description('Azure OpenAI resource URI to use for embeddings (e.g. https://<resource>.openai.azure.com).')
param openAiResourceUri string

@description('Azure OpenAI embeddings deployment identifier.')
param openAiEmbeddingsDeploymentId string

@description('Azure OpenAI model name used for embeddings.')
param openAiEmbeddingsModelName string

@description('Dimensionality of the embedding vector returned by the Azure OpenAI deployment.')
@minValue(1)
param openAiEmbeddingDimensions int = 1536

@description('Name of the index that will receive projected documents.')
param targetIndexName string

@description('Key field name on the target index representing the parent document.')
param parentKeyFieldName string = 'parent_id'

@description('Name of the vector field on the target index.')
param vectorFieldName string = 'text_vector'

@description('Name of the chunk text field on the target index.')
param chunkFieldName string = 'chunk'

@description('Name of the title field on the target index.')
param titleFieldName string = 'title'

@description('Name of the source path field on the target index.')
param sourcePathFieldName string = 'source_path'

@description('Name of the table-row index that receives projected table rows from the custom skill.')
param tableTargetIndexName string

@description('Name of the Azure Function App used by the table extraction custom Web API skill.')
param tableExtractionFunctionAppName string

@description('Default host name of the Azure Function App used by the table extraction custom Web API skill.')
param tableExtractionFunctionHostName string

@description('HTTP route for the table extraction custom Web API skill.')
param tableExtractionFunctionRoute string = 'table-extraction-skill'

@description('Name of the vector output produced by the embedding skill.')
param embeddingOutputFieldName string = 'text_vector'

@description('Projection mode controlling parent-child behavior.')
param indexProjectionMode string = 'skipIndexingParentDocuments'

@description('Value used to force redeployment of the script when changed.')
param forceUpdateTag string

var scriptName = '${uniqueString(resourceGroup().id, searchServiceName, skillsetName)}-createskillset'

resource createSkillset 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
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
        name: 'SKILLSET_NAME'
        value: skillsetName
      }
      {
        name: 'SKILLSET_DESCRIPTION'
        value: skillsetDescription
      }
      {
        name: 'SPLIT_SKILL_NAME'
        value: splitSkillName
      }
      {
        name: 'EMBEDDING_SKILL_NAME'
        value: embeddingSkillName
      }
      {
        name: 'SPLIT_SKILL_OUTPUT_TARGET_NAME'
        value: splitSkillOutputTargetName
      }
      {
        name: 'DEFAULT_LANGUAGE_CODE'
        value: defaultLanguageCode
      }
      {
        name: 'TEXT_SPLIT_MODE'
        value: textSplitMode
      }
      {
        name: 'PAGE_OVERLAP_LENGTH'
        value: string(pageOverlapLength)
      }
      {
        name: 'MAXIMUM_PAGE_LENGTH'
        value: string(maximumPageLength)
      }
      {
        name: 'MAXIMUM_PAGES_TO_TAKE'
        value: string(maximumPagesToTake)
      }
      {
        name: 'SPLIT_UNIT'
        value: splitUnit
      }
      {
        name: 'DOCUMENT_CONTENT_SOURCE_PATH'
        value: documentContentSourcePath
      }
      {
        name: 'DOCUMENT_CONTEXT'
        value: documentContext
      }
      {
        name: 'PAGE_SOURCE_CONTEXT'
        value: pageSourceContext
      }
      {
        name: 'TITLE_SOURCE_PATH'
        value: titleSourcePath
      }
      {
        name: 'SOURCE_PATH_SOURCE_PATH'
        value: sourcePathSourcePath
      }
      {
        name: 'OPENAI_RESOURCE_URI'
        value: openAiResourceUri
      }
      {
        name: 'OPENAI_EMBEDDINGS_DEPLOYMENT_ID'
        value: openAiEmbeddingsDeploymentId
      }
      {
        name: 'OPENAI_EMBEDDINGS_MODEL_NAME'
        value: openAiEmbeddingsModelName
      }
      {
        name: 'OPENAI_EMBEDDING_DIMENSIONS'
        value: string(openAiEmbeddingDimensions)
      }
      {
        name: 'TARGET_INDEX_NAME'
        value: targetIndexName
      }
      {
        name: 'PARENT_KEY_FIELD_NAME'
        value: parentKeyFieldName
      }
      {
        name: 'VECTOR_FIELD_NAME'
        value: vectorFieldName
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
        name: 'SOURCE_PATH_FIELD_NAME'
        value: sourcePathFieldName
      }
      {
        name: 'TABLE_TARGET_INDEX_NAME'
        value: tableTargetIndexName
      }
      {
        name: 'TABLE_EXTRACTION_FUNCTION_APP_NAME'
        value: tableExtractionFunctionAppName
      }
      {
        name: 'TABLE_EXTRACTION_FUNCTION_HOSTNAME'
        value: tableExtractionFunctionHostName
      }
      {
        name: 'TABLE_EXTRACTION_FUNCTION_ROUTE'
        value: tableExtractionFunctionRoute
      }
      {
        name: 'EMBEDDING_OUTPUT_FIELD_NAME'
        value: embeddingOutputFieldName
      }
      {
        name: 'INDEX_PROJECTION_MODE'
        value: indexProjectionMode
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

API_VERSION="2026-04-01"
ADMIN_KEY=$(az search admin-key show --resource-group "$RESOURCE_GROUP_NAME" --service-name "$SEARCH_SERVICE_NAME" --query primaryKey -o tsv)
FUNCTION_KEY=$(az functionapp keys list --resource-group "$RESOURCE_GROUP_NAME" --name "$TABLE_EXTRACTION_FUNCTION_APP_NAME" --query 'functionKeys.default' -o tsv 2>/dev/null || true)

if [[ -z "$ADMIN_KEY" ]]; then
  echo "Failed to retrieve search admin key" >&2
  exit 1
fi

OPENAI_RESOURCE_URI=${OPENAI_RESOURCE_URI%/}
PAGE_SOURCE_CONTEXT=${PAGE_SOURCE_CONTEXT:-/document/pages/*}
DOCUMENT_CONTEXT=${DOCUMENT_CONTEXT:-/document}
DOCUMENT_CONTENT_SOURCE_PATH=${DOCUMENT_CONTENT_SOURCE_PATH:-/document/content}
TITLE_SOURCE_PATH=${TITLE_SOURCE_PATH:-/document/title}
SOURCE_PATH_SOURCE_PATH=${SOURCE_PATH_SOURCE_PATH:-/document/metadata_storage_path}
EMBEDDING_OUTPUT_FIELD_NAME=${EMBEDDING_OUTPUT_FIELD_NAME:-text_vector}
EMBEDDING_INPUT_SOURCE="$PAGE_SOURCE_CONTEXT"
VECTOR_SOURCE_PATH="$PAGE_SOURCE_CONTEXT/$EMBEDDING_OUTPUT_FIELD_NAME"
CHUNK_SOURCE_PATH="$PAGE_SOURCE_CONTEXT"
SELECTOR_SOURCE_CONTEXT="$PAGE_SOURCE_CONTEXT"
SPLIT_SKILL_OUTPUT_TARGET_NAME=${SPLIT_SKILL_OUTPUT_TARGET_NAME:-pages}
TABLE_ROWS_CONTEXT="/document/tableRows/*"
TEXT_PAGES_CONTEXT="/document/textPages/*"
TABLE_ROW_VECTOR_FIELD_NAME="content_vector"
TABLE_EXTRACTION_FUNCTION_URI="https://$TABLE_EXTRACTION_FUNCTION_HOSTNAME/api/$TABLE_EXTRACTION_FUNCTION_ROUTE"
if [[ -n "$FUNCTION_KEY" ]]; then
  TABLE_EXTRACTION_FUNCTION_URI="$TABLE_EXTRACTION_FUNCTION_URI?code=$FUNCTION_KEY"
fi

PAYLOAD_FILE=$(mktemp)
trap 'rm -f "$PAYLOAD_FILE"' EXIT

cat <<EOF >"$PAYLOAD_FILE"
{
  "name": "$SKILLSET_NAME",
  "description": "$SKILLSET_DESCRIPTION",
  "skills": [
    {
      "@odata.type": "#Microsoft.Skills.Custom.WebApiSkill",
      "name": "tableExtractionSkill",
      "description": "Extract normalized table rows with Azure Document Intelligence",
      "context": "$DOCUMENT_CONTEXT",
      "uri": "$TABLE_EXTRACTION_FUNCTION_URI",
      "httpMethod": "POST",
      "timeout": "PT230S",
      "batchSize": 1,
      "degreeOfParallelism": 1,
      "inputs": [
        {
          "name": "metadata_storage_path",
          "source": "/document/metadata_storage_path"
        },
        {
          "name": "metadata_storage_name",
          "source": "/document/metadata_storage_name"
        }
      ],
      "outputs": [
        {
          "name": "tableRows",
          "targetName": "tableRows"
        },
        {
          "name": "textPages",
          "targetName": "textPages"
        }
      ]
    },
    {
      "@odata.type": "#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill",
      "name": "fullTextPageEmbeddingSkill",
      "description": "Generate embeddings for full PDF page text extracted by Document Intelligence",
      "context": "$TEXT_PAGES_CONTEXT",
      "resourceUri": "$OPENAI_RESOURCE_URI",
      "deploymentId": "$OPENAI_EMBEDDINGS_DEPLOYMENT_ID",
      "dimensions": $OPENAI_EMBEDDING_DIMENSIONS,
      "modelName": "$OPENAI_EMBEDDINGS_MODEL_NAME",
      "inputs": [
        {
          "name": "text",
          "source": "$TEXT_PAGES_CONTEXT/content"
        }
      ],
      "outputs": [
        {
          "name": "embedding",
          "targetName": "$VECTOR_FIELD_NAME"
        }
      ]
    },
    {
      "@odata.type": "#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill",
      "name": "tableRowEmbeddingSkill",
      "description": "Generate embeddings for extracted table rows",
      "context": "$TABLE_ROWS_CONTEXT",
      "resourceUri": "$OPENAI_RESOURCE_URI",
      "deploymentId": "$OPENAI_EMBEDDINGS_DEPLOYMENT_ID",
      "dimensions": $OPENAI_EMBEDDING_DIMENSIONS,
      "modelName": "$OPENAI_EMBEDDINGS_MODEL_NAME",
      "inputs": [
        {
          "name": "text",
          "source": "$TABLE_ROWS_CONTEXT/content"
        }
      ],
      "outputs": [
        {
          "name": "embedding",
          "targetName": "$TABLE_ROW_VECTOR_FIELD_NAME"
        }
      ]
    }
  ],
  "indexProjections": {
    "selectors": [
      {
        "targetIndexName": "$TARGET_INDEX_NAME",
        "parentKeyFieldName": "$PARENT_KEY_FIELD_NAME",
        "sourceContext": "$TEXT_PAGES_CONTEXT",
        "mappings": [
          {
            "name": "$VECTOR_FIELD_NAME",
            "source": "$TEXT_PAGES_CONTEXT/$VECTOR_FIELD_NAME"
          },
          {
            "name": "$CHUNK_FIELD_NAME",
            "source": "$TEXT_PAGES_CONTEXT/content"
          },
          {
            "name": "$TITLE_FIELD_NAME",
            "source": "$TEXT_PAGES_CONTEXT/title"
          },
          {
            "name": "$SOURCE_PATH_FIELD_NAME",
            "source": "$TEXT_PAGES_CONTEXT/source_path"
          }
        ]
      },
      {
        "targetIndexName": "$TABLE_TARGET_INDEX_NAME",
        "parentKeyFieldName": "$PARENT_KEY_FIELD_NAME",
        "sourceContext": "$TABLE_ROWS_CONTEXT",
        "mappings": [
          { "name": "document_name", "source": "$TABLE_ROWS_CONTEXT/document_name" },
          { "name": "source_path", "source": "$TABLE_ROWS_CONTEXT/source_path" },
          { "name": "page", "source": "$TABLE_ROWS_CONTEXT/page" },
          { "name": "section", "source": "$TABLE_ROWS_CONTEXT/section" },
          { "name": "table_title", "source": "$TABLE_ROWS_CONTEXT/table_title" },
          { "name": "row_kind", "source": "$TABLE_ROWS_CONTEXT/row_kind" },
          { "name": "line_number", "source": "$TABLE_ROWS_CONTEXT/line_number" },
          { "name": "item", "source": "$TABLE_ROWS_CONTEXT/item" },
          { "name": "category", "source": "$TABLE_ROWS_CONTEXT/category" },
          { "name": "request_amount", "source": "$TABLE_ROWS_CONTEXT/request_amount" },
          { "name": "authorized_amount", "source": "$TABLE_ROWS_CONTEXT/authorized_amount" },
          { "name": "delta_amount", "source": "$TABLE_ROWS_CONTEXT/delta_amount" },
          { "name": "adjustment_reason", "source": "$TABLE_ROWS_CONTEXT/adjustment_reason" },
          { "name": "content", "source": "$TABLE_ROWS_CONTEXT/content" },
          { "name": "raw_text", "source": "$TABLE_ROWS_CONTEXT/raw_text" },
          { "name": "columns_json", "source": "$TABLE_ROWS_CONTEXT/columns_json" },
          { "name": "$TABLE_ROW_VECTOR_FIELD_NAME", "source": "$TABLE_ROWS_CONTEXT/$TABLE_ROW_VECTOR_FIELD_NAME" }
        ]
      }
    ],
    "parameters": {
      "projectionMode": "$INDEX_PROJECTION_MODE"
    }
  }
}
EOF

az rest --method put \
  --uri "$SEARCH_SERVICE_ENDPOINT/skillsets/$SKILLSET_NAME" \
  --url-parameters "api-version=$API_VERSION" \
  --headers "Content-Type=application/json" "api-key=$ADMIN_KEY" \
  --skip-authorization-header \
  --body @"$PAYLOAD_FILE"
'''
  }
}

output deploymentScriptName string = createSkillset.name
