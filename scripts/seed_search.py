import asyncio
import base64
import logging
import os
import subprocess
from pathlib import Path
from typing import Iterable

import aiohttp
from azure.core.credentials import AzureKeyCredential
from azure.core.exceptions import HttpResponseError, ResourceExistsError as AzureResourceExistsError
from azure.identity.aio import AzureCliCredential, ChainedTokenCredential, ManagedIdentityCredential
from azure.search.documents.indexes.aio import SearchIndexerClient
from azure.storage.blob.aio import BlobServiceClient
from dotenv import load_dotenv


logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger("seed-search")

REPO_ROOT = Path(__file__).resolve().parents[1]
DOCS_DIR = REPO_ROOT / "docs"
AZD_ENV_DIR = REPO_ROOT / ".azure"


def load_azd_environment() -> None:
    env_name = os.getenv("AZURE_ENV_NAME", "").strip()
    candidates = []
    if env_name:
        candidates.append(AZD_ENV_DIR / env_name / ".env")
    if AZD_ENV_DIR.exists():
        candidates.extend(sorted(AZD_ENV_DIR.glob("*/.env"), reverse=True))

    for candidate in candidates:
        if candidate.exists():
            load_dotenv(candidate, override=False)
            logger.info("Loaded azd environment from %s", candidate)
            return


def iter_docs() -> Iterable[Path]:
    if not DOCS_DIR.exists():
        return []
    return (
        path
        for path in DOCS_DIR.rglob("*")
        if path.is_file() and not any(part.startswith(".") for part in path.relative_to(DOCS_DIR).parts)
    )


def require_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"{name} is required. Run this after azd provision/up so deployment outputs are available.")
    return value


def get_search_audience() -> str:
    return "https://search.azure.us" if os.getenv("CLOUD_NAME") == "AzureUSGovernment" else "https://search.azure.com"


def get_search_admin_key() -> str | None:
    search_service_name = os.getenv("SEARCH_SERVICE_NAME", "").strip()
    resource_group_name = os.getenv("RESOURCE_GROUP_NAME", "").strip() or os.getenv("AZURE_RESOURCE_GROUP", "").strip()
    if not search_service_name or not resource_group_name:
        return None

    command = [
        "az",
        "search",
        "admin-key",
        "show",
        "--resource-group",
        resource_group_name,
        "--service-name",
        search_service_name,
        "--query",
        "primaryKey",
        "-o",
        "tsv",
    ]
    result = subprocess.run(command, check=False, capture_output=True, text=True)
    if result.returncode != 0:
        logger.warning("Could not retrieve Search admin key; falling back to Azure RBAC: %s", result.stderr.strip())
        return None
    return result.stdout.strip() or None


def get_env_or_default(name: str, default: str) -> str:
    return os.getenv(name, "").strip() or default


def get_search_resource_names() -> dict[str, str]:
    environment_name = require_env("AZURE_ENV_NAME")
    return {
        "data_source": get_env_or_default("SEARCH_DATA_SOURCE_NAME", f"{environment_name}-storage-ds"),
        "index": require_env("SEARCH_INDEX_NAME"),
        "skillset": get_env_or_default("SEARCH_SKILLSET_NAME", f"{environment_name}-index-and-vectorize-skillset"),
        "indexer": require_env("SEARCH_INDEXER_NAME"),
    }


def encode_blob_path_key(value: str) -> str:
    encoded = base64.urlsafe_b64encode(value.encode("utf-8")).decode("ascii")
    return encoded.rstrip("=")


async def search_request(method: str, path: str, admin_key: str, payload: dict | None = None) -> None:
    search_endpoint = require_env("SEARCH_SERVICE_ENDPOINT").rstrip("/")
    url = f"{search_endpoint}{path}"
    headers = {"api-key": admin_key, "Content-Type": "application/json"}
    timeout = aiohttp.ClientTimeout(total=60, connect=10)
    async with aiohttp.ClientSession(headers=headers, timeout=timeout) as session:
        async with session.request(method, url, json=payload) as response:
            if response.status >= 400:
                body = await response.text()
                raise RuntimeError(f"Search request failed ({method} {url}, {response.status}): {body}")


async def configure_search() -> None:
    admin_key = get_search_admin_key()
    if not admin_key:
        raise RuntimeError("Unable to retrieve the Search admin key required to configure Search objects")

    names = get_search_resource_names()
    storage_account_id = require_env("STORAGE_ACCOUNT_ID")
    openai_endpoint = require_env("OPENAI_ACCOUNT_ENDPOINT").rstrip("/")
    embeddings_deployment_name = require_env("OPENAI_EMBEDDINGS_DEPLOYMENT_NAME")
    embeddings_model_name = require_env("OPENAI_EMBEDDINGS_DEPLOYMENT_MODEL")
    embeddings_dimensions = int(get_env_or_default("OPENAI_EMBEDDINGS_DIMENSIONS", "1536"))
    container_name = require_env("STORAGE_ACCOUNT_CONTAINER_NAME")

    vector_field = "text_vector"
    chunk_field = "chunk"
    title_field = "title"
    source_path_field = "source_path"
    semantic_configuration = "index-and-vectorize-semantic-configuration"
    vector_algorithm = "index-and-vectorize-algorithm"
    vector_profile = "index-and-vectorize-azureOpenAi-text-profile"
    vectorizer = "index-and-vectorize-azureOpenAi-text-vectorizer"

    data_source_payload = {
        "name": names["data_source"],
        "type": "azureblob",
        "credentials": {"connectionString": f"ResourceId={storage_account_id}"},
        "container": {"name": container_name},
    }
    await search_request("PUT", f"/datasources/{names['data_source']}?api-version=2026-04-01", admin_key, data_source_payload)
    logger.info("Configured Search data source %s", names["data_source"])

    index_payload = {
        "name": names["index"],
        "fields": [
            {
                "name": "chunk_id",
                "type": "Edm.String",
                "searchable": True,
                "filterable": False,
                "retrievable": True,
                "stored": True,
                "sortable": True,
                "facetable": False,
                "key": True,
                "analyzer": "keyword",
                "synonymMaps": [],
            },
            {
                "name": "parent_id",
                "type": "Edm.String",
                "searchable": False,
                "filterable": True,
                "retrievable": True,
                "stored": True,
                "sortable": False,
                "facetable": False,
                "key": False,
                "synonymMaps": [],
            },
            {
                "name": chunk_field,
                "type": "Edm.String",
                "searchable": True,
                "filterable": False,
                "retrievable": True,
                "stored": True,
                "sortable": False,
                "facetable": False,
                "key": False,
                "synonymMaps": [],
            },
            {
                "name": title_field,
                "type": "Edm.String",
                "searchable": True,
                "filterable": True,
                "retrievable": True,
                "stored": True,
                "sortable": False,
                "facetable": True,
                "key": False,
                "synonymMaps": [],
            },
            {
                "name": source_path_field,
                "type": "Edm.String",
                "searchable": False,
                "filterable": True,
                "retrievable": True,
                "stored": True,
                "sortable": False,
                "facetable": False,
                "key": False,
                "synonymMaps": [],
            },
            {
                "name": vector_field,
                "type": "Collection(Edm.Single)",
                "searchable": True,
                "filterable": False,
                "retrievable": True,
                "stored": True,
                "sortable": False,
                "facetable": False,
                "key": False,
                "dimensions": embeddings_dimensions,
                "vectorSearchProfile": vector_profile,
                "synonymMaps": [],
            },
        ],
        "scoringProfiles": [],
        "suggesters": [],
        "analyzers": [],
        "normalizers": [],
        "tokenizers": [],
        "tokenFilters": [],
        "charFilters": [],
        "similarity": {"@odata.type": "#Microsoft.Azure.Search.BM25Similarity"},
        "semantic": {
            "defaultConfiguration": semantic_configuration,
            "configurations": [
                {
                    "name": semantic_configuration,
                    "prioritizedFields": {
                        "titleField": {"fieldName": title_field},
                        "prioritizedContentFields": [{"fieldName": chunk_field}],
                        "prioritizedKeywordsFields": [],
                    },
                }
            ],
        },
        "vectorSearch": {
            "algorithms": [
                {
                    "name": vector_algorithm,
                    "kind": "hnsw",
                    "hnswParameters": {"metric": "cosine", "m": 4, "efConstruction": 400, "efSearch": 500},
                }
            ],
            "profiles": [{"name": vector_profile, "algorithm": vector_algorithm, "vectorizer": vectorizer}],
            "vectorizers": [
                {
                    "name": vectorizer,
                    "kind": "azureOpenAI",
                    "azureOpenAIParameters": {
                        "resourceUri": openai_endpoint,
                        "deploymentId": embeddings_deployment_name,
                        "modelName": embeddings_model_name,
                    },
                }
            ],
            "compressions": [],
        },
    }
    await search_request("PUT", f"/indexes('{names['index']}')?api-version=2026-04-01", admin_key, index_payload)
    logger.info("Configured Search index %s", names["index"])

    skillset_payload = {
        "name": names["skillset"],
        "description": "Skillset to chunk documents and generate embeddings",
        "skills": [
            {
                "@odata.type": "#Microsoft.Skills.Text.SplitSkill",
                "name": "splitSkill",
                "description": "Split content into smaller chunks",
                "context": "/document",
                "defaultLanguageCode": "en",
                "textSplitMode": "pages",
                "maximumPageLength": 2000,
                "pageOverlapLength": 500,
                "maximumPagesToTake": 0,
                "inputs": [{"name": "text", "source": "/document/content"}],
                "outputs": [{"name": "textItems", "targetName": "pages"}],
            },
            {
                "@odata.type": "#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill",
                "name": "embeddingSkill",
                "description": "Generate embeddings for each chunk",
                "context": "/document/pages/*",
                "resourceUri": openai_endpoint,
                "deploymentId": embeddings_deployment_name,
                "dimensions": embeddings_dimensions,
                "modelName": embeddings_model_name,
                "inputs": [{"name": "text", "source": "/document/pages/*"}],
                "outputs": [{"name": "embedding", "targetName": vector_field}],
            },
        ],
        "indexProjections": {
            "selectors": [
                {
                    "targetIndexName": names["index"],
                    "parentKeyFieldName": "parent_id",
                    "sourceContext": "/document/pages/*",
                    "mappings": [
                        {"name": vector_field, "source": f"/document/pages/*/{vector_field}"},
                        {"name": chunk_field, "source": "/document/pages/*"},
                        {"name": title_field, "source": "/document/title"},
                        {"name": source_path_field, "source": "/document/metadata_storage_path"},
                    ],
                }
            ],
            "parameters": {"projectionMode": "skipIndexingParentDocuments"},
        },
    }
    await search_request("PUT", f"/skillsets/{names['skillset']}?api-version=2026-04-01", admin_key, skillset_payload)
    logger.info("Configured Search skillset %s", names["skillset"])

    indexer_payload = {
        "name": names["indexer"],
        "dataSourceName": names["data_source"],
        "skillsetName": names["skillset"],
        "targetIndexName": names["index"],
        "parameters": {
            "maxFailedItems": -1,
            "maxFailedItemsPerBatch": -1,
            "configuration": {
                "dataToExtract": "contentAndMetadata",
                "parsingMode": "default",
                "failOnUnsupportedContentType": False,
                "failOnUnprocessableDocument": False,
                "indexStorageMetadataOnlyForOversizedDocuments": True,
            },
        },
        "fieldMappings": [{"sourceFieldName": "metadata_storage_name", "targetFieldName": title_field}],
    }
    await search_request("PUT", f"/indexers('{names['indexer']}')?api-version=2026-04-01", admin_key, indexer_payload)
    logger.info("Configured Search indexer %s", names["indexer"])


async def upload_docs(credential: ChainedTokenCredential) -> int:
    blob_endpoint = require_env("STORAGE_ACCOUNT_BLOB_ENDPOINT")
    container_name = require_env("STORAGE_ACCOUNT_CONTAINER_NAME")

    docs = list(iter_docs())
    if not docs:
        logger.info("No files found in %s; skipping upload", DOCS_DIR)
        return 0

    blob_service = BlobServiceClient(account_url=blob_endpoint, credential=credential)
    async with blob_service:
        container = blob_service.get_container_client(container_name)
        try:
            await container.create_container()
            logger.info("Created blob container %s", container_name)
        except AzureResourceExistsError:
            pass

        for path in docs:
            blob_name = path.relative_to(DOCS_DIR).as_posix()
            with path.open("rb") as content:
                try:
                    await container.upload_blob(name=blob_name, data=content, overwrite=True)
                except HttpResponseError as exc:
                    if getattr(exc, "error_code", "") == "AuthorizationPermissionMismatch":
                        logger.warning(
                            "Could not upload %s yet because Blob data-plane RBAC has not propagated for this identity. "
                            "Rerun `uv run python scripts/seed_search.py` after role propagation completes.",
                            blob_name,
                        )
                        continue
                    raise
            logger.info("Uploaded %s", blob_name)

    return len(docs)


async def run_indexer(credential: ChainedTokenCredential) -> None:
    search_endpoint = require_env("SEARCH_SERVICE_ENDPOINT")
    indexer_name = require_env("SEARCH_INDEXER_NAME")
    admin_key = get_search_admin_key()

    if admin_key:
        indexer_client = SearchIndexerClient(endpoint=search_endpoint, credential=AzureKeyCredential(admin_key))
    else:
        indexer_client = SearchIndexerClient(
            endpoint=search_endpoint,
            credential=credential,
            audience=get_search_audience(),
        )
    async with indexer_client:
        try:
            await indexer_client.run_indexer(indexer_name)
            logger.info("Started Azure AI Search indexer %s", indexer_name)
        except HttpResponseError as exc:
            if exc.status_code == 429:
                logger.warning("Indexer %s is already running or throttled: %s", indexer_name, exc.message)
                return
            if exc.status_code == 409 and "Another indexer invocation is currently in progress" in str(exc):
                logger.info("Indexer %s is already running", indexer_name)
                return
            raise


async def main() -> None:
    load_azd_environment()
    credential = ChainedTokenCredential(AzureCliCredential(), ManagedIdentityCredential())
    async with credential:
        uploaded_count = await upload_docs(credential)
        try:
            await configure_search()
            await run_indexer(credential)
        except (aiohttp.ClientError, asyncio.TimeoutError) as exc:
            logger.warning(
                "Uploaded docs, but could not reach the Azure AI Search data-plane endpoint to configure Search or run the indexer: %s",
                exc,
            )
            logger.warning("Rerun `uv run python scripts/seed_search.py` from a network that can reach SEARCH_SERVICE_ENDPOINT.")
    logger.info("Seeded %s file(s) from %s", uploaded_count, DOCS_DIR)


if __name__ == "__main__":
    asyncio.run(main())