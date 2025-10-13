# AI Search with MCP – Infrastructure

This project provisions the infrastructure for an Azure AI Search solution that now includes an Azure AI Foundry (Azure OpenAI) account with a GPT-4o deployment. The templates are written in Bicep and designed to be deployed with the Azure Developer CLI (`azd`).

## Architecture 🏗️

The deployment creates the following resources in a single resource group:

- Azure AI Search service with a system-assigned identity.
- Storage account and private blob container for ingesting search content.
- User-assigned managed identity used by deployment scripts.
- Azure AI Foundry (Azure OpenAI) account with a GPT-4o deployment.
 - Azure AI Foundry (Azure OpenAI) account with GPT-4o and Ada embeddings deployments.
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
