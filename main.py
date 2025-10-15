import asyncio
import logging
import os
from datetime import date, datetime
from decimal import Decimal
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List, Optional

from azure.core.exceptions import HttpResponseError
from azure.identity import AzureAuthorityHosts, DefaultAzureCredential
from azure.search.documents import SearchClient
from dotenv import load_dotenv
from fastmcp import FastMCP

mcp = FastMCP("Azure AI Search MCP")
logger = logging.getLogger(__name__)

_ENV_DIRECTORY = Path.cwd() / ".azure"
_ENV_PREFIX = "avcoe-*"
_DEFAULT_SELECT_FIELDS = ["title", "chunk"]


def _make_jsonable(value: Any) -> Any:
    """Convert Azure SDK values into JSON-serialisable primitives."""

    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, dict):
        return {key: _make_jsonable(val) for key, val in value.items()}
    if isinstance(value, (list, tuple)):
        return [_make_jsonable(item) for item in value]
    return str(value)


def _escape_filter_value(value: str) -> str:
    """Escape single quotes for OData filter expressions."""

    return value.replace("'", "''")


@lru_cache(maxsize=1)
def _load_environment() -> Path:
    """Load the first matching env file so credentials resolve via DefaultAzureCredential."""

    env_file = next(
        (
            candidate / ".env"
            for candidate in _ENV_DIRECTORY.glob(_ENV_PREFIX)
            if (candidate / ".env").exists()
        ),
        None,
    )
    if env_file is None:
        raise FileNotFoundError(
            "Could not locate an avcoe-* environment directory under .azure"
        )

    load_dotenv(dotenv_path=env_file, override=False)
    logger.info("Loaded environment variables from %s", env_file)
    return env_file


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

    credential = DefaultAzureCredential(authority=authority_host)
    return SearchClient(endpoint=endpoint, index_name=resolved_index, credential=credential, audience=audience)


@mcp.tool()
async def list_facets(
    facet_name: str = "title",
    search_text: str = "*",
) -> Dict[str, Any]:
    """Return facet values for the configured Azure AI Search index."""

    client = _get_search_client()

    def _run() -> List[Dict[str, Any]]:
        results = client.search(
            search_text,
            facets=[facet_name],
            top=0,
        )
        facets = results.get_facets().get(facet_name, [])
        return [_make_jsonable(facet) for facet in facets]

    try:
        values = await asyncio.to_thread(_run)
    except HttpResponseError as exc:
        logger.exception("Facet retrieval failed for %s", facet_name)
        raise RuntimeError(
            f"Failed to retrieve facets for '{facet_name}': {str(exc)}"
        ) from exc

    return {
        "facet": facet_name,
        "search_text": search_text,
        "values": values,
    }


@mcp.tool()
async def semantic_search(
    query: str,
    top: int = 3,
    facet_value: Optional[str] = None,
    select_fields: Optional[List[str]] = None,
    query_type: str = "semantic",
) -> Dict[str, Any]:
    """Execute a search query and return JSON-serialisable documents."""

    if top <= 0:
        raise ValueError("top must be greater than zero")

    client = _get_search_client()
    select = select_fields or _DEFAULT_SELECT_FIELDS
    allowed_query_types = {"semantic", "simple"}
    if query_type not in allowed_query_types:
        raise ValueError(f"query_type must be one of {sorted(allowed_query_types)}")

    filter_expression: Optional[str] = None
    if facet_value:
        filter_expression = f"title eq '{_escape_filter_value(facet_value)}'"

    def _run() -> Dict[str, Any]:
        search_kwargs: Dict[str, Any] = {
            "include_total_count": True,
            "top": top,
            "select": select,
            "query_type": query_type,
        }
        if filter_expression:
            search_kwargs["filter"] = filter_expression

        results = client.search(query, **search_kwargs)
        documents = [_make_jsonable(dict(hit)) for hit in results]
        total = results.get_count()
        return {
            "query": query,
            "query_type": query_type,
            "top": top,
            "filter": filter_expression,
            "select": select,
            "total_count": total,
            "documents": documents,
        }

    try:
        payload = await asyncio.to_thread(_run)
    except HttpResponseError as exc:
        logger.exception("Search request failed for query '%s'", query)
        raise RuntimeError(f"Search request failed: {str(exc)}") from exc

    return payload


if __name__ == "__main__":
    mcp.run(transport="streamable-http", host="0.0.0.0", port=8000)
