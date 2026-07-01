# Azure AI Search MCP

This repo contains a deployable FastMCP server for Azure AI Search. It provisions Azure AI Search, Azure Blob Storage, Azure OpenAI embeddings, and an App Service-hosted MCP endpoint with `azd`, then seeds the search container from the local `docs/` folder and starts the indexer.

## What It Deploys

- Azure AI Search with a system-assigned managed identity.
- Azure Blob Storage with a private `aisearchdata` container for source documents.
- Azure OpenAI with a `text-embedding-ada-002` embeddings deployment.
- An AI Search data source, vector index, skillset, and blob indexer using integrated vectorization.
- An App Service-hosted FastMCP server with managed identity access to Search and Blob Storage.

The Search pipeline follows the current Microsoft guidance for blob indexing and integrated vectorization: a blob data source, Text Split skill, Azure OpenAI Embedding skill, projected chunk index, Azure OpenAI vectorizer, semantic configuration, and an on-demand indexer run.

## MCP Tools

`semantic_search` runs hybrid semantic search with query-time vectorization. Results omit vector payloads and include retrievable fields such as `chunk`, `title`, `source_path`, and Search metadata.

`get_image_from_content_path` downloads image content from Blob Storage when a search result includes an explicit `content_path` field. The default Bicep index is text-first, so agents should only call this tool when that field is actually present in search results.

## Deploy

Install and sign in with the Azure Developer CLI, then run:

```bash
azd auth login
azd up
```

During `azd up`, the `postprovision` hook runs:

```bash
uv run python scripts/seed_search.py
```

That script loads azd outputs, uploads every non-hidden file under `docs/` into the provisioned blob container, and starts the Azure AI Search indexer. The current sample content is [docs/NDAA - 2027.pdf](docs/NDAA%20-%202027.pdf).

Because the storage account disables shared-key access, the signed-in Azure CLI user must have data-plane upload permission on the storage account, such as **Storage Blob Data Contributor**. The Search indexer itself reads blobs through the Search service managed identity, which the Bicep deployment grants **Storage Blob Data Reader**.

## Common Settings

Set azd environment values before `azd up` when you want to override defaults:

```bash
azd env set AZURE_LOCATION eastus
azd env set SEARCH_SERVICE_SKU basic
azd env set STORAGE_ACCOUNT_SKU Standard_LRS
azd env set CLOUD_NAME AzureCloud
```

For Azure Government, set:

```bash
azd env set CLOUD_NAME AzureUSGovernment
```

After deployment, azd writes outputs such as `SEARCH_SERVICE_ENDPOINT`, `SEARCH_INDEX_NAME`, `SEARCH_INDEXER_NAME`, `STORAGE_ACCOUNT_BLOB_ENDPOINT`, and `STORAGE_ACCOUNT_CONTAINER_NAME` to the environment. The MCP server reads those values automatically in Azure App Service and from `.azure/<env>/.env` during local development.

## Local Development

Use `uv` for local Python operations:

```bash
uv sync
uv run python main.py
```

The server listens on `http://localhost:8000` using FastMCP streamable HTTP transport.

To re-upload `docs/` and run the indexer after changing source files:

```bash
uv run python scripts/seed_search.py
```

## Authentication

The MCP server supports optional bearer-token validation:

- Microsoft Entra ID JWKS validation when `AZURE_AD_REQUIRE_AUTH=true`.
- Symmetric HS256 JWT validation when `MCP_AUTH_SECRET` is set.
- No MCP-layer auth when neither is configured, which is suitable only for local development.

For Entra ID auth, configure:

```env
AZURE_AD_REQUIRE_AUTH=true
AZURE_AD_TENANT_ID=<tenant-id>
AZURE_AD_CLIENT_ID=<mcp-app-client-id>
```

Requests without a valid `Authorization: Bearer <token>` header receive HTTP 401 when auth is enabled.

## Notes

- The blob indexer is configured for `contentAndMetadata`, explicit source attribution through `source_path`, and tolerant handling of individual unsupported or unprocessable files.
- Integrated vectorization uses the same embedding model for indexing and query-time vectorization, as recommended by Azure AI Search docs.
- Indexer execution is on demand after docs upload. If an indexer run is already in progress, the seeding script logs the condition and leaves the active run alone.
