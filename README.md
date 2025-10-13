# AI Search with MCP – Infrastructure

This project provisions the infrastructure for an Azure AI Search solution that now includes an Azure AI Foundry (Azure OpenAI) account with a GPT-4o deployment. The templates are written in Bicep and designed to be deployed with the Azure Developer CLI (`azd`).

## Architecture 🏗️

The deployment creates the following resources in a single resource group:

- Azure AI Search service with a system-assigned identity.
- Storage account and private blob container for ingesting search content.
- User-assigned managed identity used by deployment scripts.
- Azure AI Foundry (Azure OpenAI) account with a GPT-4o deployment.
 - Azure AI Foundry (Azure OpenAI) account with GPT-4o and Ada embeddings deployments.
- Role assignment that grants the Azure AI Search service identity contributor access to the OpenAI resource for Entra ID inference.
- Role assignments that allow the search service to read blobs and the deployment script to manage the search service.

## Deployment

```powershell
azd auth login
azd up
```

You can override defaults by setting environment variables before running `azd up`, for example:

```powershell
$env:AZURE_ENV_NAME = "mysandbox"
$env:AZURE_LOCATION = "eastus"
$env:AZURE_OPENAI_MODEL_NAME = "gpt-4o"
$env:AZURE_OPENAI_MODEL_VERSION = "2024-11-20"
$env:AZURE_OPENAI_DEPLOYMENT_CAPACITY = "10"
$env:AZURE_OPENAI_EMBEDDINGS_MODEL_NAME = "text-embedding-ada-002"
$env:AZURE_OPENAI_EMBEDDINGS_MODEL_VERSION = "2"
$env:AZURE_OPENAI_EMBEDDINGS_DEPLOYMENT_CAPACITY = "10"
azd up
```

`azd` automatically maps environment variables with the `AZURE_` prefix to Bicep parameters.

## Bicep Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `openAiModelName` | Model identifier deployed to Azure AI Foundry. | `gpt-4o` |
| `openAiModelVersion` | Specific model version to deploy. | `2024-11-20` |
| `openAiDeploymentCapacity` | Throughput units allocated to the GPT-4o deployment. | `10` |
| `openAiEmbeddingsModelName` | Embeddings model identifier deployed to Azure AI Foundry. | `text-embedding-ada-002` |
| `openAiEmbeddingsModelVersion` | Specific embeddings model version to deploy. | `2` |
| `openAiEmbeddingsDeploymentCapacity` | Throughput units allocated to the embeddings deployment. | `10` |

Other parameters such as `environmentName`, `location`, and `resourceGroupName` continue to be supplied by `azd`.

## Outputs

After deployment, `azd` surfaces the following outputs for integration:

- `OPENAI_ACCOUNT_ENDPOINT`
- `OPENAI_DEPLOYMENT_NAME`
- `OPENAI_EMBEDDINGS_DEPLOYMENT_NAME`
- `SEARCH_SERVICE_ENDPOINT`
- `STORAGE_ACCOUNT_BLOB_ENDPOINT`

Use these values in application configuration or automation steps that consume the AI Search and GPT-4o capabilities.

## Role assignments

The templates automatically grant the Azure AI Search service's system-assigned managed identity the **Cognitive Services OpenAI Contributor** role over the Azure OpenAI account. This permission is required for Entra ID-based access from Azure AI Search to both the GPT-4o and embeddings deployments. If additional workloads need access, assign the appropriate Azure OpenAI role (for example, **Cognitive Services OpenAI User**) to their managed identities at the OpenAI account scope.

## Manual validation with `az rest`

If you need to validate the index, skillset, or indexer definitions outside of an `azd` deployment, the repository includes ready-to-send payloads (`index-test.json`, `skillset-test.json`, and `indexer-test.json`). Update the placeholder values (for example, the OpenAI resource URI) and run the following from PowerShell:

```powershell
$resourceGroup = "<resource-group-name>"
$searchServiceName = "<search-service-name>"
$searchEndpoint = "https://$searchServiceName.search.windows.net"
$apiVersion = "2024-09-01-preview"
$indexName = "avcoe-demo-ai-search-mcp-index-and-vectorize"
$skillsetName = "avcoe-demo-ai-search-mcp-index-and-vectorize-skillset"
$indexerName = "avcoe-demo-ai-search-mcp-index-and-vectorize-indexer"
$indexPayloadPath = "$(Resolve-Path ./index-test.json)"
$skillsetPayloadPath = "$(Resolve-Path ./skillset-test.json)"
$indexerPayloadPath = "$(Resolve-Path ./indexer-test.json)"

$adminKey = az search admin-key show `
	--resource-group $resourceGroup `
	--service-name $searchServiceName `
	--query primaryKey -o tsv

az rest --method put `
	--uri "$searchEndpoint/indexes('$indexName')" `
	--headers "Content-Type=application/json" "api-key=$adminKey" `
	--url-parameters "api-version=$apiVersion" `
	--body @$indexPayloadPath `
	--skip-authorization-header

az rest --method put `
	--uri "$searchEndpoint/skillsets/$skillsetName" `
	--headers "Content-Type=application/json" "api-key=$adminKey" `
	--url-parameters "api-version=$apiVersion" `
	--body @$skillsetPayloadPath `
	--skip-authorization-header

az rest --method put `
	--uri "$searchEndpoint/indexers('$indexerName')" `
	--headers "Content-Type=application/json" "api-key=$adminKey" `
	--url-parameters "api-version=$apiVersion" `
	--body @$indexerPayloadPath `
	--skip-authorization-header
```

The manual calls help troubleshoot API schema issues quickly and mirror the deployment script logic used by the Bicep modules.
