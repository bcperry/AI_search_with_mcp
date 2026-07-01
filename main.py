import asyncio
import logging
import os
import re
from urllib.parse import urlparse, unquote
from datetime import date, datetime
from decimal import Decimal
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List, NamedTuple, Optional

from azure.core.exceptions import HttpResponseError
from azure.core.credentials import TokenCredential
from azure.identity import (
    AzureAuthorityHosts,
    AzureCliCredential,
    ChainedTokenCredential,
    EnvironmentCredential,
    InteractiveBrowserCredential,
    ManagedIdentityCredential,
)
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.indexes.models import SearchFieldDataType
from azure.search.documents.models import VectorizableTextQuery
from azure.storage.blob import BlobServiceClient
from dotenv import load_dotenv
from fastmcp import FastMCP
from fastmcp.server.auth.providers.jwt import JWTVerifier
from fastmcp.utilities.types import Image
import uvicorn

logger = logging.getLogger(__name__)

# Load root .env early so MCP_AUTH_* vars are available at import time
load_dotenv(override=False)


def _apply_cloud_authority_from_env() -> None:
    """Set AZURE_AUTHORITY_HOST for Azure Gov when CLOUD_NAME indicates government cloud."""
    cloud_name = os.getenv("CLOUD_NAME", "").strip()
    if cloud_name == "AzureUSGovernment" and not os.getenv("AZURE_AUTHORITY_HOST"):
        os.environ["AZURE_AUTHORITY_HOST"] = AzureAuthorityHosts.AZURE_GOVERNMENT
        logger.info("Set AZURE_AUTHORITY_HOST to %s", AzureAuthorityHosts.AZURE_GOVERNMENT)


def _build_default_credential(authority_host: str) -> TokenCredential:
    """Create a credential chain that avoids broker auth issues and supports Gov cloud."""
    tenant_id = os.getenv("AZURE_TENANT_ID")

    environment_credential = EnvironmentCredential(
        additionally_allowed_tenants=["*"],
        **({"authority": authority_host} if authority_host else {}),
    )
    managed_identity_credential = ManagedIdentityCredential()
    azure_cli_credential = AzureCliCredential(tenant_id=tenant_id)
    interactive_browser_credential = InteractiveBrowserCredential(
        tenant_id=tenant_id,
        additionally_allowed_tenants=["*"],
        authority=authority_host,
    )

    return ChainedTokenCredential(
        environment_credential,
        managed_identity_credential,
        azure_cli_credential,
        interactive_browser_credential,
    )


_apply_cloud_authority_from_env()


def _get_azure_ad_login_host() -> str:
    """Return the Azure AD login host based on CLOUD_NAME."""
    cloud_name = os.getenv("CLOUD_NAME", "").strip()
    if cloud_name == "AzureUSGovernment":
        return "login.microsoftonline.us"
    return "login.microsoftonline.com"


def _build_auth() -> Optional[JWTVerifier]:
    """Return a JWTVerifier based on auth configuration priority.

    Priority:
    1. AZURE_AD_REQUIRE_AUTH=true  → Azure AD JWKS (RS256)
    2. MCP_AUTH_SECRET set         → symmetric HS256 (existing behavior)
    3. Neither                     → None (no auth)
    """
    # --- Azure AD JWKS-based auth (RS256) ---
    require_aad = os.getenv("AZURE_AD_REQUIRE_AUTH", "false").strip().lower() == "true"
    if require_aad:
        tenant_id = os.getenv("AZURE_AD_TENANT_ID", "").strip()
        client_id = os.getenv("AZURE_AD_CLIENT_ID", "").strip()
        if not tenant_id:
            raise RuntimeError(
                "AZURE_AD_REQUIRE_AUTH is true but AZURE_AD_TENANT_ID is not set"
            )
        if not client_id:
            raise RuntimeError(
                "AZURE_AD_REQUIRE_AUTH is true but AZURE_AD_CLIENT_ID is not set"
            )
        login_host = _get_azure_ad_login_host()
        issuer = f"https://{login_host}/{tenant_id}/v2.0"
        jwks_uri = f"https://{login_host}/{tenant_id}/discovery/v2.0/keys"
        custom_audience = os.getenv("AZURE_AD_AUDIENCE", "").strip()
        audience: str | list[str] = (
            custom_audience if custom_audience
            else [client_id, f"api://{client_id}"]
        )
        logger.info(
            "Azure AD auth enabled – issuer=%s, audience=%s",
            issuer,
            audience,
        )
        return JWTVerifier(
            jwks_uri=jwks_uri,
            issuer=issuer,
            audience=audience,
            algorithm="RS256",
        )

    # --- Existing symmetric-key auth (HS256) ---
    secret = os.getenv("MCP_AUTH_SECRET")
    if secret:
        logger.info("MCP_AUTH_SECRET auth enabled (HS256)")
        return JWTVerifier(
            public_key=secret,
            algorithm="HS256",
            issuer=os.getenv("MCP_AUTH_ISSUER", "mcp-issuer"),
            audience=os.getenv("MCP_AUTH_AUDIENCE", "azure-ai-search-mcp"),
        )

    # --- No auth ---
    logger.warning("No authentication configured – running WITHOUT authentication")
    return None


mcp = FastMCP("Azure AI Search MCP", auth=_build_auth())

_ENV_DIRECTORY = Path.cwd() / ".azure"
_ENV_PREFIX = "avcoe-*"
_VALID_CONTAINER_NAME_PATTERN = re.compile(r'^[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])?$')
_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".tif", ".tiff"}
_NON_IMAGE_EXTENSIONS = {
    ".pdf", ".docx", ".doc", ".xlsx", ".xls",
    ".pptx", ".ppt", ".txt", ".csv", ".html", ".htm",
}
_BLOB_FALLBACK_SCAN_LIMIT = 2000
_BLOB_FALLBACK_PAGE_SIZE = 200


def _make_jsonable(value: Any) -> Any:
    """Convert Azure SDK values into JSON-serialisable primitives."""

    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    if hasattr(value, "as_dict") and callable(value.as_dict):
        return _make_jsonable(value.as_dict())
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, dict):
        result: Dict[str, Any] = {}
        for key, val in value.items():
            if key == "additional_properties" and val is None:
                continue
            result[key] = _make_jsonable(val)
        return result
    if isinstance(value, (list, tuple)):
        return [_make_jsonable(item) for item in value]
    return str(value)


def _should_exclude_search_field(field_name: str, value: Any) -> bool:
    """Exclude vector and embedding payloads from search results."""

    normalized_name = field_name.lower()
    if "vector" in normalized_name or "embedding" in normalized_name:
        return True
    if isinstance(value, (list, tuple)) and value:
        if all(isinstance(item, (int, float)) for item in value):
            return True
    return False


def _sanitize_search_hit(hit: Dict[str, Any]) -> Dict[str, Any]:
    """Return a search hit with vector fields removed and values made JSON-safe."""

    result: Dict[str, Any] = {}
    for key, value in hit.items():
        if _should_exclude_search_field(key, value):
            continue

        output_key = key
        if key == "@search.reranker_score":
            output_key = "@search.rerankerScore"

        result[output_key] = _make_jsonable(value)
    return result


@lru_cache(maxsize=1)
def _load_environment() -> Optional[Path]:
    """Load the first matching env file so Azure credentials resolve locally.
    
    Only loads from .env file when running locally. In deployed environments (Azure),
    environment variables should already be set via App Settings.
    """
    # Check if we're running in Azure (common Azure environment variables)
    if os.getenv("WEBSITE_INSTANCE_ID") or os.getenv("WEBSITE_SITE_NAME"):
        logger.info("Running in Azure - using existing environment variables")
        return None

    env_file = next(
        (
            candidate / ".env"
            for candidate in _ENV_DIRECTORY.glob(_ENV_PREFIX)
            if (candidate / ".env").exists()
        ),
        None,
    )
    if env_file is None:
        root_env = Path.cwd() / ".env"
        if root_env.exists():
            load_dotenv(dotenv_path=root_env, override=False)
            logger.info("Loaded environment variables from %s", root_env)
            _apply_cloud_authority_from_env()
            return root_env

        logger.warning(
            "Could not locate an avcoe-* environment directory under .azure and no root .env found - using existing environment variables"
        )
        _apply_cloud_authority_from_env()
        return None

    load_dotenv(dotenv_path=env_file, override=False)
    logger.info("Loaded environment variables from %s", env_file)
    _apply_cloud_authority_from_env()
    return env_file


@lru_cache(maxsize=1)
def _get_blob_service_client() -> Optional[BlobServiceClient]:
    """Construct a BlobServiceClient for downloading images from Azure Blob Storage."""
    _load_environment()
    blob_endpoint = os.getenv("STORAGE_ACCOUNT_BLOB_ENDPOINT")
    if not blob_endpoint:
        logger.warning("STORAGE_ACCOUNT_BLOB_ENDPOINT is not set – image downloads disabled")
        return None

    cloud_name = os.getenv("CLOUD_NAME", "").strip()
    if cloud_name == "AzureUSGovernment":
        authority_host = AzureAuthorityHosts.AZURE_GOVERNMENT
    else:
        authority_host = AzureAuthorityHosts.AZURE_PUBLIC_CLOUD

    credential = _build_default_credential(authority_host)
    return BlobServiceClient(account_url=blob_endpoint, credential=credential)


def _get_default_blob_container_name() -> Optional[str]:
    """Return the configured default blob container name when available."""
    _load_environment()
    container_name = os.getenv("STORAGE_ACCOUNT_CONTAINER_NAME")
    if not container_name:
        logger.warning("STORAGE_ACCOUNT_CONTAINER_NAME is not set – blob-only content paths may fail")
        return None
    return container_name


def _is_valid_blob_container_name(value: str) -> bool:
    """Return True when the value is a plausible Azure Blob container name."""
    if '--' in value:
        return False
    return bool(_VALID_CONTAINER_NAME_PATTERN.fullmatch(value))


def _is_likely_image_content_path(value: Optional[str]) -> bool:
    """Return True unless the path has a known non-image document extension."""
    if not value:
        return False

    normalized_value = unquote(value.strip())
    if not normalized_value:
        return False

    parsed = urlparse(normalized_value)
    path_value = parsed.path if parsed.scheme and parsed.netloc else normalized_value
    suffix = Path(path_value).suffix.lower()
    return suffix not in _NON_IMAGE_EXTENSIONS


def _iter_limited_blob_names(client: BlobServiceClient, container_name: str):
    """Yield blob names from a container with a hard cap to avoid full-container scans."""
    scanned = 0
    pager = client.get_container_client(container_name).list_blobs(name_starts_with="").by_page(
        results_per_page=_BLOB_FALLBACK_PAGE_SIZE
    )
    for page in pager:
        for blob_item in page:
            candidate_name = getattr(blob_item, "name", "")
            if candidate_name:
                yield candidate_name
            scanned += 1
            if scanned >= _BLOB_FALLBACK_SCAN_LIMIT:
                logger.warning(
                    "Stopped blob fallback scan after %s entries in container '%s'",
                    _BLOB_FALLBACK_SCAN_LIMIT,
                    container_name,
                )
                return


def _build_blob_suffix_candidates(blob_name: str) -> List[str]:
    """Build likely blob suffixes for exact-image fallback matching."""

    candidates: List[str] = []
    markers = ["/normalized_images_", "_normalized_images_"]
    for marker in markers:
        marker_index = blob_name.rfind(marker)
        if marker_index < 0:
            continue

        candidates.append(blob_name[marker_index + 1 :])
        candidates.append(blob_name[marker_index + len(marker) - len("normalized_images_") :])

    basename = Path(blob_name).name
    if basename:
        candidates.append(basename)

    seen = set()
    result: List[str] = []
    for candidate in candidates:
        if not candidate or candidate in seen:
            continue
        seen.add(candidate)
        result.append(candidate)
    return result


async def _download_blob_image(content_path: str) -> Optional[Image]:
    """Download an image from blob storage using a full URL or blob-relative content_path.

    Returns an Image object if successful, None otherwise.
    """
    client = _get_blob_service_client()
    if client is None:
        return None

    normalized_input = unquote((content_path or "").strip())
    if not _is_likely_image_content_path(normalized_input):
        suffix = Path(urlparse(normalized_input).path).suffix.lower() or Path(normalized_input).suffix.lower()
        logger.warning("Rejected non-image content_path (extension=%s): %s", suffix, content_path)
        return None

    parsed = urlparse(normalized_input)

    # Accept either a full blob URL or a relative blob path.
    if parsed.scheme and parsed.netloc:
        path_value = parsed.path.lstrip("/")
        logger.debug("Stripped URL prefix from content_path: %s -> %s", content_path, path_value)
    else:
        path_value = normalized_input.lstrip("/")

    parts = path_value.split("/", 1)
    default_container_name = _get_default_blob_container_name()

    if len(parts) != 2:
        logger.warning("Invalid content_path format: %s", content_path)
        return None

    candidate_container_name, candidate_blob_name = parts
    if default_container_name and not _is_valid_blob_container_name(candidate_container_name):
        container_name = default_container_name
        blob_name = path_value
    else:
        container_name = candidate_container_name
        blob_name = candidate_blob_name

    def _find_blob_by_suffix() -> Optional[str]:
        suffix_candidates = _build_blob_suffix_candidates(blob_name)
        if not suffix_candidates:
            return None

        for candidate_name in _iter_limited_blob_names(client, container_name):
            for expected_suffix in suffix_candidates:
                if candidate_name.endswith(expected_suffix):
                    return candidate_name
        return None

    def _download() -> bytes:
        blob_client = client.get_blob_client(container=container_name, blob=blob_name)
        try:
            return blob_client.download_blob().readall()
        except Exception:
            fallback_blob_name = _find_blob_by_suffix()
            if not fallback_blob_name:
                raise

            logger.info(
                "Exact blob not found for content_path. Using suffix fallback blob '%s'",
                fallback_blob_name,
            )
            fallback_blob_client = client.get_blob_client(container=container_name, blob=fallback_blob_name)
            return fallback_blob_client.download_blob().readall()

    try:
        data = await asyncio.to_thread(_download)
    except Exception:
        logger.exception("Failed to download image from %s", content_path)
        return None

    # Determine image format from the file extension
    ext = Path(path_value).suffix.lower().lstrip(".")
    fmt = {"jpg": "jpeg", "jpeg": "jpeg", "png": "png", "gif": "gif", "webp": "webp"}.get(ext, "jpeg")
    return Image(data=data, format=fmt)


@lru_cache(maxsize=1)
def _get_search_client(index_name: Optional[str] = None) -> SearchClient:
    """Construct a SearchClient configured for the current cloud."""

    _load_environment()
    endpoint = os.getenv("SEARCH_SERVICE_ENDPOINT")
    if not endpoint:
        raise RuntimeError("SEARCH_SERVICE_ENDPOINT is not defined in the environment")

    resolved_index = index_name or os.getenv("SEARCH_INDEX_NAME")
    if not resolved_index:
        raise RuntimeError("SEARCH_INDEX_NAME is not defined in the environment")

    cloud_name = os.getenv("CLOUD_NAME", "").strip()
    if cloud_name == "AzureUSGovernment":
        authority_host = AzureAuthorityHosts.AZURE_GOVERNMENT
        audience = "https://search.azure.us"
    else:
        authority_host = AzureAuthorityHosts.AZURE_PUBLIC_CLOUD
        audience = "https://search.azure.com"

    logger.info(
        "Creating SearchClient for endpoint %s, index %s, authority %s",
        endpoint,
        resolved_index,
        authority_host,
    )

    credential = _build_default_credential(authority_host)
    return SearchClient(endpoint=endpoint, index_name=resolved_index, credential=credential, audience=audience)


class IndexSchema(NamedTuple):
    select_fields: List[str]
    vector_field_name: str
    semantic_configuration_name: Optional[str]


@lru_cache(maxsize=1)
def _get_search_index_client() -> SearchIndexClient:
    """Construct a SearchIndexClient for index schema introspection."""
    _load_environment()
    endpoint = os.getenv("SEARCH_SERVICE_ENDPOINT")
    if not endpoint:
        raise RuntimeError("SEARCH_SERVICE_ENDPOINT is not defined in the environment")

    cloud_name = os.getenv("CLOUD_NAME", "").strip()
    if cloud_name == "AzureUSGovernment":
        authority_host = AzureAuthorityHosts.AZURE_GOVERNMENT
        audience = "https://search.azure.us"
    else:
        authority_host = AzureAuthorityHosts.AZURE_PUBLIC_CLOUD
        audience = "https://search.azure.com"

    credential = _build_default_credential(authority_host)
    return SearchIndexClient(endpoint=endpoint, credential=credential, audience=audience)


@lru_cache(maxsize=1)
def _get_index_schema() -> IndexSchema:
    """Introspect the search index to discover select fields, vector field, and semantic config.

    Returns a cached IndexSchema. Env overrides take highest priority. Falls back to
    safe defaults if introspection fails.
    """
    index_name = os.getenv("SEARCH_INDEX_NAME", "").strip()

    # --- Env overrides (highest priority) ---
    env_select = os.getenv("SEARCH_SELECT_FIELDS", "").strip()
    env_vector = os.getenv("SEARCH_VECTOR_FIELD_NAME", "").strip()
    env_semantic = os.getenv("SEARCH_SEMANTIC_CONFIGURATION_NAME", "").strip()

    if env_select and env_vector:
        schema = IndexSchema(
            select_fields=[f.strip() for f in env_select.split(",") if f.strip()],
            vector_field_name=env_vector,
            semantic_configuration_name=env_semantic or None,
        )
        logger.info(
            "Using env-override schema: select_fields=%s, vector_field='%s', semantic_config='%s'",
            schema.select_fields, schema.vector_field_name, schema.semantic_configuration_name,
        )
        return schema

    # --- Introspect index schema ---
    try:
        client = _get_search_index_client()
        index = client.get_index(index_name)
    except Exception:
        logger.warning(
            "Failed to introspect index '%s' – falling back to no $select filter",
            index_name,
            exc_info=True,
        )
        return IndexSchema(
            select_fields=[],
            vector_field_name=env_vector or "text_vector",
            semantic_configuration_name=env_semantic or None,
        )

    # Classify fields
    select_fields: List[str] = []
    vector_field_name: Optional[str] = None
    for field in index.fields:
        is_vector = (
            getattr(field, "vector_search_dimensions", None) is not None
            or getattr(field, "vector_search_profile_name", None) is not None
        )
        if is_vector:
            if vector_field_name is None:
                vector_field_name = field.name
        elif not getattr(field, "hidden", False) and field.type != SearchFieldDataType.ComplexType:
            select_fields.append(field.name)

    # Discover semantic configuration
    semantic_config_name: Optional[str] = None
    semantic_search_settings = getattr(index, "semantic_search", None)
    if semantic_search_settings:
        semantic_config_name = getattr(semantic_search_settings, "default_configuration_name", None)
        if not semantic_config_name:
            configs = getattr(semantic_search_settings, "configurations", None) or []
            if configs:
                semantic_config_name = configs[0].name

    # Apply partial env overrides
    schema = IndexSchema(
        select_fields=[f.strip() for f in env_select.split(",") if f.strip()] if env_select else select_fields,
        vector_field_name=env_vector or vector_field_name or "text_vector",
        semantic_configuration_name=env_semantic or semantic_config_name,
    )

    logger.info(
        "Introspected index '%s': select_fields=%s, vector_field='%s', semantic_config='%s'",
        index_name, schema.select_fields, schema.vector_field_name, schema.semantic_configuration_name,
    )
    return schema


@mcp.tool()
async def semantic_search(
    query: str,
    top: int = 3,
) -> Dict[str, Any]:
    """Run hybrid semantic search and return the portal-style non-vector hit data.

    Args:
        query: Natural language search query.
        top: Maximum number of hits to return.

    Returns:
        A dictionary containing semantic answers, total count, and result hits with vector fields removed.

    Raises:
        ValueError: If top <= 0
        RuntimeError: If the search request fails or the service is unreachable
    """

    if top <= 0:
        raise ValueError("top must be greater than zero")

    client = _get_search_client()
    schema = _get_index_schema()
    endpoint = os.getenv("SEARCH_SERVICE_ENDPOINT") or ""
    index_name = os.getenv("SEARCH_INDEX_NAME") or ""

    def _run() -> Dict[str, Any]:
        search_kwargs: Dict[str, Any] = {
            "include_total_count": True,
            "top": top,
            "query_type": "semantic",
            "semantic_query": query,
            "query_answer": "extractive",
            "query_answer_count": top,
            "query_caption": "extractive",
            "query_caption_highlight_enabled": True,
            "vector_queries": [
                VectorizableTextQuery(
                    text=query,
                    fields=schema.vector_field_name,
                )
            ],
        }
        if schema.select_fields:
            search_kwargs["select"] = list(schema.select_fields)
        if schema.semantic_configuration_name:
            search_kwargs["semantic_configuration_name"] = schema.semantic_configuration_name

        results = client.search(query, **search_kwargs)
        hits = [_sanitize_search_hit(dict(hit)) for hit in results]
        answers = [_make_jsonable(answer) for answer in results.get_answers() or []]

        return {
            "@odata.context": f"{endpoint}/indexes('{index_name}')/$metadata#docs(*)",
            "@odata.count": results.get_count(),
            "@search.answers": answers,
            "@search.nextPageParameters": {
                "search": query,
                "count": True,
                "queryType": "semantic",
                "semanticConfiguration": schema.semantic_configuration_name,
                "captions": "extractive",
                "answers": f"extractive|count-{top}",
                "select": ",".join(schema.select_fields) if schema.select_fields else "*",
                "vectorQueries": [
                    {
                        "kind": "text",
                        "fields": schema.vector_field_name,
                        "text": query,
                    }
                ],
            },
            "value": hits,
        }

    try:
        return await asyncio.to_thread(_run)
    except HttpResponseError as exc:
        logger.exception("Search request failed for query '%s'", query)
        raise RuntimeError(f"Search request failed: {str(exc)}") from exc


@mcp.tool(output_schema=None)
async def get_image_from_content_path(
    content_path: str,
) -> Image:
    """Download an image from Azure Blob Storage and return MCP Image content.

    IMPORTANT: Only call this tool when a semantic_search result hit contains an explicit
    'content_path' field. If the search results do NOT include a 'content_path' field in
    the returned hits, there are no images available to retrieve — do not call this tool.

    Never construct a URL from parent_id, title, chunk_id, or any other field. Only pass
    the literal content_path value from a search result hit.

    Users usually do not want screenshots of text or scanned pages with little visual
    value. Use this tool when semantic_search describes actual useful or interesting
    visual content that should be shown directly to the user.

    Args:
        content_path: The content_path value from a semantic_search result hit. Pass
            the value exactly as it appears in the search result.

    Returns:
        MCP Image content suitable for clients that render image blocks.

    Raises:
        ValueError: If content_path is empty or has a known document extension.
        RuntimeError: If the image cannot be downloaded.
    """

    normalized_path = (content_path or "").strip()
    if not normalized_path:
        raise ValueError("content_path is required and cannot be empty")
    if not _is_likely_image_content_path(normalized_path):
        suffix = Path(urlparse(unquote(normalized_path)).path).suffix.lower() or Path(unquote(normalized_path)).suffix.lower()
        raise ValueError(
            f"content_path '{normalized_path}' has a document extension ({suffix}). "
            f"This tool requires the content_path field from a semantic_search result "
            f"that contains image content. If search results do not include a "
            f"content_path field, there are no images available to retrieve."
        )

    image = await _download_blob_image(normalized_path)
    if image is None:
        raise RuntimeError(
            f"Unable to download image from content_path '{normalized_path}'. Verify STORAGE_ACCOUNT_BLOB_ENDPOINT and RBAC."
        )

    return image


# Eagerly load index schema at startup to surface config errors early
_get_index_schema()


class McpPathCompatibilityApp:
    def __init__(self, app: Any) -> None:
        self.app = app

    async def __call__(self, scope: Dict[str, Any], receive: Any, send: Any) -> None:
        if scope.get("type") == "http" and scope.get("path") == "/mcp":
            scope = dict(scope)
            scope["path"] = "/mcp/"
        await self.app(scope, receive, send)


if __name__ == "__main__":
    app = mcp.http_app(path="/mcp/", transport="streamable-http")
    uvicorn.run(
        McpPathCompatibilityApp(app),
        host="0.0.0.0",
        port=8000,
        lifespan="on",
        timeout_graceful_shutdown=0,
    )
