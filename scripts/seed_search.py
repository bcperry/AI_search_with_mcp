import asyncio
import argparse
import base64
import hashlib
import logging
import os
import re
import subprocess
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable

import aiohttp
import fitz
from azure.ai.documentintelligence.aio import DocumentIntelligenceClient
from azure.core.credentials import AzureKeyCredential
from azure.core.exceptions import HttpResponseError, ResourceExistsError as AzureResourceExistsError
from azure.identity.aio import AzureCliCredential, ChainedTokenCredential, ManagedIdentityCredential, get_bearer_token_provider
from azure.search.documents.aio import SearchClient
from azure.storage.blob.aio import BlobServiceClient
from dotenv import load_dotenv
from openai import AsyncAzureOpenAI


logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger("seed-search")

REPO_ROOT = Path(__file__).resolve().parents[1]
DOCS_DIR = REPO_ROOT / "docs"
AZD_ENV_DIR = REPO_ROOT / ".azure"
LEADER_DOTS_PATTERN = re.compile(r"\s*\.{2,}\s*")
MONEY_PATTERN = re.compile(r"^[\[(]?\s*[\-–]?\d{1,3}(?:,\d{3})*\s*[\])]?$")
LINE_NUMBER_PATTERN = re.compile(r"^\d{3}[A-Z]?$")
SECTION_PATTERN = re.compile(r"^SEC\.\s+(\d+[A-Z]?)\.\s*(.*)$")
BATCH_SIZE = 500
MAIN_VECTOR_FIELD = "text_vector"
TABLE_ROW_VECTOR_FIELD = "content_vector"
EMBED_MAX_INPUT_CHARS = 32000
MAX_EMBED_REQUEST_CHARS = 32000


def _is_noise_line(value: str) -> bool:
    return (
        (value.isdigit() and not LINE_NUMBER_PATTERN.fullmatch(value))
        or value.startswith("•HR ")
        or value in {"Line", "Item", "FY 2027", "Request", "House", "Authorized", "(In Thousands of Dollars)"}
    )


def _is_amount(value: str) -> bool:
    if LINE_NUMBER_PATTERN.fullmatch(value.strip()):
        return False
    return bool(MONEY_PATTERN.fullmatch(value.strip()))


def _parse_amount(value: str) -> int | None:
    if not _is_amount(value):
        return None
    is_negative = "[" in value or "(" in value or "-" in value or "–" in value
    digits = re.sub(r"[^0-9]", "", value)
    if not digits:
        return None
    amount = int(digits)
    return -amount if is_negative else amount


def _clean_pdf_line(value: str) -> str:
    return markdown_cell(value).replace("—", "-").strip()


def _is_heading(value: str) -> bool:
    if _is_noise_line(value) or _is_amount(value) or LINE_NUMBER_PATTERN.fullmatch(value):
        return False
    letters = [char for char in value if char.isalpha()]
    return bool(letters) and all(char.upper() == char for char in letters)


def _make_row_id(*parts: object) -> str:
    raw_value = "|".join(str(part) for part in parts)
    return hashlib.sha256(raw_value.encode("utf-8")).hexdigest()


def _format_thousands(value: int | None) -> str:
    if value is None:
        return "not listed"
    return f"{value:,} thousand dollars"


def _build_funding_row_content(row: "TableRowDocument") -> str:
    parts = [
        f"Section {row.section} {row.table_title} funding row.",
        f"Account: {row.category}.",
    ]
    if row.line_number:
        parts.append(f"Line {row.line_number}.")
    if row.item:
        parts.append(f"Item: {row.item}.")
    parts.extend(
        [
            f"FY 2027 request: {_format_thousands(row.request_amount)}.",
            f"House authorized: {_format_thousands(row.authorized_amount)}.",
        ]
    )
    if row.delta_amount is not None:
        parts.append(f"Adjustment: {_format_thousands(row.delta_amount)}.")
    if row.adjustment_reason:
        parts.append(f"Adjustment reason: {row.adjustment_reason}.")
    parts.append(f"Source: {row.document_name} page {row.page}.")
    return " ".join(parts)


@dataclass
class TableRowDocument:
    id: str
    document_name: str
    source_path: str
    page: int
    section: str
    table_title: str
    row_kind: str
    content: str
    raw_text: str
    line_number: str = ""
    item: str = ""
    category: str = ""
    request_amount: int | None = None
    authorized_amount: int | None = None
    delta_amount: int | None = None
    adjustment_reason: str = ""
    columns: dict[str, str] = field(default_factory=dict)

    def as_search_document(self) -> dict[str, Any]:
        document = {
            "id": self.id,
            "document_name": self.document_name,
            "source_path": self.source_path,
            "page": self.page,
            "section": self.section,
            "table_title": self.table_title,
            "row_kind": self.row_kind,
            "line_number": self.line_number,
            "item": self.item,
            "category": self.category,
            "request_amount": self.request_amount,
            "authorized_amount": self.authorized_amount,
            "delta_amount": self.delta_amount,
            "adjustment_reason": self.adjustment_reason,
            "content": self.content,
            "raw_text": self.raw_text,
            "columns_json": json_dumps_stable(self.columns),
        }
        return {key: value for key, value in document.items() if value is not None}

    @property
    def embedding_source(self) -> str:
        return self.content


@dataclass(frozen=True)
class MainPageDocument:
    chunk_id: str
    parent_id: str
    chunk: str
    title: str
    source_path: str

    def as_search_document(self) -> dict[str, str]:
        return {
            "chunk_id": self.chunk_id,
            "parent_id": self.parent_id,
            "chunk": self.chunk,
            "title": self.title,
            "source_path": self.source_path,
        }

    @property
    def embedding_source(self) -> str:
        return self.chunk


@dataclass(frozen=True)
class ExtractedPage:
    page_number: int
    lines: list[str]


@dataclass(frozen=True)
class ExtractedTable:
    page_number: int
    table_index: int
    rows: list[list[str]]


def json_dumps_stable(value: dict[str, str]) -> str:
    if not value:
        return "{}"
    import json

    return json.dumps(value, sort_keys=True, separators=(",", ":"))


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


def iter_source_pdfs() -> Iterable[Path]:
    if not DOCS_DIR.exists():
        return []
    return (
        path
        for path in DOCS_DIR.rglob("*.pdf")
        if path.is_file()
        and not any(part.startswith(".") for part in path.relative_to(DOCS_DIR).parts)
    )


def markdown_cell(value: object) -> str:
    text = "" if value is None else str(value)
    text = LEADER_DOTS_PATTERN.sub(" ", text.replace("|", "\\|"))
    return " ".join(text.split())


def markdown_cell_lines(value: object) -> list[str]:
    text = "" if value is None else str(value)
    lines = [markdown_cell(line) for line in text.splitlines()]
    return [line for line in lines if line]


def expand_multiline_row(row: list[object]) -> list[list[str]]:
    cell_lines = [markdown_cell_lines(cell) for cell in row]
    row_count = max((len(lines) for lines in cell_lines), default=0)
    if row_count <= 1:
        return [[markdown_cell(cell) for cell in row]]

    expanded_rows: list[list[str]] = []
    for row_index in range(row_count):
        expanded_rows.append(
            [lines[row_index] if row_index < len(lines) else "" for lines in cell_lines]
        )
    return expanded_rows


def _iter_detected_table_rows(pdf_path: Path, page_number: int, table_index: int, rows: list[list[object]]) -> Iterable[TableRowDocument]:
    normalized_rows: list[list[str]] = []
    for row in rows:
        for expanded_row in expand_multiline_row(row):
            if any(expanded_row):
                normalized_rows.append(expanded_row)
    if len(normalized_rows) < 2:
        return []

    header = normalized_rows[0]
    table_title = f"Page {page_number} Table {table_index}"
    row_documents: list[TableRowDocument] = []
    for row_index, row in enumerate(normalized_rows[1:], start=1):
        columns = {
            header[column_index] or f"column_{column_index + 1}": value
            for column_index, value in enumerate(row)
            if value
        }
        if not columns:
            continue
        content = " ".join(
            [
                f"Table row from {pdf_path.name} page {page_number}.",
                f"{table_title}.",
                " ".join(f"{key}: {value}." for key, value in columns.items()),
            ]
        )
        row_documents.append(
            TableRowDocument(
                id=_make_row_id(pdf_path.name, page_number, table_index, row_index, columns),
                document_name=pdf_path.name,
                source_path=pdf_path.relative_to(DOCS_DIR).as_posix(),
                page=page_number,
                section="",
                table_title=table_title,
                row_kind="detected_table",
                item=" ".join(value for value in row if value),
                category=table_title,
                content=content,
                raw_text=" | ".join(row),
                columns=columns,
            )
        )
    return row_documents


def _find_next_amount(lines: list[str], start_index: int) -> tuple[int | None, int]:
    for index in range(start_index, len(lines)):
        if _is_amount(lines[index]):
            return _parse_amount(lines[index]), index + 1
        if LINE_NUMBER_PATTERN.fullmatch(lines[index]) or SECTION_PATTERN.fullmatch(lines[index]):
            break
    return None, start_index


def _iter_funding_table_rows(pdf_path: Path, pages: Iterable[ExtractedPage]) -> Iterable[TableRowDocument]:
    rows: list[TableRowDocument] = []
    current_section = ""
    current_title = ""
    current_account = ""
    current_category = ""

    for page in pages:
        page_number = page.page_number
        lines = [_clean_pdf_line(line) for line in page.lines]
        lines = [line for line in lines if line]
        index = 0
        while index < len(lines):
            line = lines[index]
            section_match = SECTION_PATTERN.fullmatch(line)
            if section_match:
                current_section = section_match.group(1)
                current_title = section_match.group(2).title()
                current_account = ""
                current_category = ""
                index += 1
                continue

            if _is_noise_line(line):
                index += 1
                continue

            if current_section and _is_heading(line):
                if not current_account or "PROCUREMENT" in line or "AUTHORIZATION" in line:
                    current_account = line.title()
                else:
                    current_category = line.title()
                index += 1
                continue

            if not (current_section and LINE_NUMBER_PATTERN.fullmatch(line)):
                index += 1
                continue

            line_number = line
            index += 1
            item_lines: list[str] = []
            while index < len(lines) and not _is_amount(lines[index]):
                if LINE_NUMBER_PATTERN.fullmatch(lines[index]) or SECTION_PATTERN.fullmatch(lines[index]):
                    break
                if not _is_noise_line(lines[index]):
                    item_lines.append(lines[index])
                index += 1

            request_amount, index = _find_next_amount(lines, index)
            authorized_amount, index = _find_next_amount(lines, index)
            if not item_lines or request_amount is None or authorized_amount is None:
                continue

            adjustment_reason = ""
            delta_amount: int | None = None
            if index + 1 < len(lines):
                candidate_reason = lines[index]
                candidate_amount = lines[index + 1]
                if (
                    candidate_reason
                    and not _is_heading(candidate_reason)
                    and not _is_noise_line(candidate_reason)
                    and not LINE_NUMBER_PATTERN.fullmatch(candidate_reason)
                    and _is_amount(candidate_amount)
                ):
                    adjustment_reason = candidate_reason
                    delta_amount = _parse_amount(candidate_amount)
                    index += 2

            item = " ".join(item_lines)
            raw_text = " | ".join(
                value
                for value in [line_number, item, str(request_amount), str(authorized_amount), adjustment_reason]
                if value
            )
            row = TableRowDocument(
                id=_make_row_id(pdf_path.name, page_number, current_section, line_number, item),
                document_name=pdf_path.name,
                source_path=pdf_path.relative_to(DOCS_DIR).as_posix(),
                page=page_number,
                section=current_section,
                table_title=current_title or f"Section {current_section}",
                row_kind="funding_line_item",
                line_number=line_number,
                item=item,
                category=current_category or current_account,
                request_amount=request_amount,
                authorized_amount=authorized_amount,
                delta_amount=delta_amount,
                adjustment_reason=adjustment_reason,
                content="",
                raw_text=raw_text,
                columns={
                    "account": current_account,
                    "category": current_category,
                    "line_number": line_number,
                    "item": item,
                    "fy_2027_request_thousands": str(request_amount),
                    "house_authorized_thousands": str(authorized_amount),
                },
            )
            row.content = _build_funding_row_content(row)
            rows.append(row)

    return rows


def _normalize_extracted_rows(pdf_path: Path, pages: list[ExtractedPage], tables: list[ExtractedTable]) -> list[TableRowDocument]:
    row_documents: list[TableRowDocument] = []
    row_documents.extend(_iter_funding_table_rows(pdf_path, pages))
    for table in tables:
        row_documents.extend(_iter_detected_table_rows(pdf_path, table.page_number, table.table_index, table.rows))
    return row_documents


def _build_main_page_documents(pdf_path: Path, pages: list[ExtractedPage]) -> list[MainPageDocument]:
    blob_name = pdf_path.relative_to(DOCS_DIR).as_posix()
    parent_id = encode_blob_path_key(blob_name)
    documents: list[MainPageDocument] = []
    for page in pages:
        page_lines = [line for line in page.lines if line.strip()]
        if not page_lines:
            continue
        documents.append(
            MainPageDocument(
                chunk_id=_make_row_id(blob_name, "page", page.page_number),
                parent_id=parent_id,
                chunk=f"Source: {pdf_path.name} page {page.page_number}.\n\n" + "\n".join(page_lines),
                title=f"{pdf_path.name} page {page.page_number}",
                source_path=f"{blob_name}#page={page.page_number}",
            )
        )
    return documents


def _log_table_row_summary(row_documents: list[TableRowDocument]) -> None:
    row_kind_counts = Counter(row.row_kind for row in row_documents)
    section_counts = Counter(row.section for row in row_documents if row.section)

    if row_kind_counts:
        logger.info(
            "Normalized table row kinds: %s",
            ", ".join(f"{row_kind}={count}" for row_kind, count in sorted(row_kind_counts.items())),
        )
    if section_counts:
        logger.info(
            "Normalized funding rows by section: %s",
            ", ".join(f"{section}={count}" for section, count in section_counts.most_common()),
        )


def _extract_pdf_layout_with_pymupdf(pdf_path: Path) -> tuple[list[ExtractedPage], list[ExtractedTable]]:
    try:
        document = fitz.open(pdf_path)
    except Exception:
        logger.exception("Could not open PDF for fallback table extraction: %s", pdf_path)
        return [], []

    pages: list[ExtractedPage] = []
    tables: list[ExtractedTable] = []
    with document:
        for page_number, page in enumerate(document, start=1):
            pages.append(ExtractedPage(page_number=page_number, lines=page.get_text().splitlines()))
            try:
                detected_tables = page.find_tables().tables
            except Exception:
                logger.exception("Could not extract fallback table rows from %s page %s", pdf_path.name, page_number)
                continue
            for table_index, table in enumerate(detected_tables, start=1):
                tables.append(ExtractedTable(page_number=page_number, table_index=table_index, rows=table.extract()))

    return pages, tables


async def _extract_pdf_layout_with_document_intelligence(
    pdf_path: Path,
    credential: ChainedTokenCredential,
) -> tuple[list[ExtractedPage], list[ExtractedTable]] | None:
    endpoint = get_document_intelligence_endpoint()
    if not endpoint:
        return None

    document_key = get_document_intelligence_key()
    client_credential: AzureKeyCredential | ChainedTokenCredential
    if document_key:
        client_credential = AzureKeyCredential(document_key)
    else:
        client_credential = credential

    client_kwargs = {"audience": get_cognitive_services_audience()} if not document_key else {}
    client = DocumentIntelligenceClient(endpoint=endpoint, credential=client_credential, **client_kwargs)
    try:
        async with client:
            poller = await client.begin_analyze_document(
                "prebuilt-layout",
                body=pdf_path.read_bytes(),
                content_type="application/pdf",
                output_content_format="text",
            )
            result = await poller.result()
    except Exception:
        logger.exception("Document Intelligence layout extraction failed for %s", pdf_path.name)
        raise

    pages: list[ExtractedPage] = []
    for page in result.pages or []:
        page_number = int(getattr(page, "page_number", 0) or 0)
        page_lines = [line.content for line in (getattr(page, "lines", None) or []) if getattr(line, "content", None)]
        if page_number and page_lines:
            pages.append(ExtractedPage(page_number=page_number, lines=page_lines))

    tables: list[ExtractedTable] = []
    for table_index, table in enumerate(result.tables or [], start=1):
        cells = getattr(table, "cells", None) or []
        if not cells:
            continue

        row_count = max((cell.row_index for cell in cells), default=-1) + 1
        column_count = max((cell.column_index for cell in cells), default=-1) + 1
        rows = [["" for _ in range(column_count)] for _ in range(row_count)]
        page_number = 0
        for cell in cells:
            content = getattr(cell, "content", "") or ""
            rows[cell.row_index][cell.column_index] = content
            if not page_number:
                regions = getattr(cell, "bounding_regions", None) or []
                if regions:
                    page_number = int(getattr(regions[0], "page_number", 0) or 0)
        if page_number:
            tables.append(ExtractedTable(page_number=page_number, table_index=table_index, rows=rows))

    logger.info(
        "Document Intelligence extracted %s page(s) and %s table(s) from %s",
        len(pages),
        len(tables),
        pdf_path.name,
    )
    return pages, tables


async def extract_pdf_content(
    credential: ChainedTokenCredential,
) -> tuple[list[MainPageDocument], list[TableRowDocument]]:
    page_documents: list[MainPageDocument] = []
    row_documents: list[TableRowDocument] = []
    for pdf_path in iter_source_pdfs():
        extracted_layout = await _extract_pdf_layout_with_document_intelligence(pdf_path, credential)
        if extracted_layout is None:
            logger.info("Using PyMuPDF fallback extraction for %s", pdf_path.name)
            extracted_layout = _extract_pdf_layout_with_pymupdf(pdf_path)

        pages, tables = extracted_layout
        page_documents.extend(_build_main_page_documents(pdf_path, pages))
        row_documents.extend(_normalize_extracted_rows(pdf_path, pages, tables))

    logger.info(
        "Extracted %s full-text page(s) and %s normalized table row(s)",
        len(page_documents),
        len(row_documents),
    )
    _log_table_row_summary(row_documents)
    return page_documents, row_documents


def require_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"{name} is required. Run this after azd provision/up so deployment outputs are available.")
    return value


def get_search_audience() -> str:
    return "https://search.azure.us" if os.getenv("CLOUD_NAME") == "AzureUSGovernment" else "https://search.azure.com"


def get_cognitive_services_audience() -> str:
    return "https://cognitiveservices.azure.us" if os.getenv("CLOUD_NAME") == "AzureUSGovernment" else "https://cognitiveservices.azure.com"


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


def get_document_intelligence_key() -> str | None:
    account_name = os.getenv("DOCUMENT_INTELLIGENCE_ACCOUNT_NAME", "").strip()
    resource_group_name = os.getenv("RESOURCE_GROUP_NAME", "").strip() or os.getenv("AZURE_RESOURCE_GROUP", "").strip()
    if not account_name or not resource_group_name:
        return None

    command = [
        "az",
        "cognitiveservices",
        "account",
        "keys",
        "list",
        "--resource-group",
        resource_group_name,
        "--name",
        account_name,
        "--query",
        "key1",
        "-o",
        "tsv",
    ]
    result = subprocess.run(command, check=False, capture_output=True, text=True)
    if result.returncode != 0:
        logger.warning("Could not retrieve Document Intelligence key; falling back to Azure RBAC: %s", result.stderr.strip())
        return None
    return result.stdout.strip() or None


def get_document_intelligence_endpoint() -> str | None:
    endpoint = os.getenv("DOCUMENT_INTELLIGENCE_ENDPOINT", "").strip()
    return endpoint.rstrip("/") if endpoint else None


def get_env_or_default(name: str, default: str) -> str:
    return os.getenv(name, "").strip() or default


def get_search_resource_names() -> dict[str, str]:
    environment_name = require_env("AZURE_ENV_NAME")
    return {
        "index": require_env("SEARCH_INDEX_NAME"),
        "table_index": get_env_or_default("SEARCH_TABLE_ROW_INDEX_NAME", f"{environment_name}-table-rows"),
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


async def search_json(method: str, path: str, admin_key: str, payload: dict | None = None) -> dict | None:
    search_endpoint = require_env("SEARCH_SERVICE_ENDPOINT").rstrip("/")
    url = f"{search_endpoint}{path}"
    headers = {"api-key": admin_key, "Content-Type": "application/json"}
    timeout = aiohttp.ClientTimeout(total=60, connect=10)
    async with aiohttp.ClientSession(headers=headers, timeout=timeout) as session:
        async with session.request(method, url, json=payload) as response:
            if response.status == 404:
                return None
            if response.status >= 400:
                body = await response.text()
                raise RuntimeError(f"Search request failed ({method} {url}, {response.status}): {body}")
            if response.status == 204:
                return None
            return await response.json()


async def configure_search() -> None:
    admin_key = get_search_admin_key()
    if not admin_key:
        raise RuntimeError("Unable to retrieve the Search admin key required to configure Search objects")

    names = get_search_resource_names()
    openai_endpoint = require_env("OPENAI_ACCOUNT_ENDPOINT").rstrip("/")
    embeddings_deployment_name = require_env("OPENAI_EMBEDDINGS_DEPLOYMENT_NAME")
    embeddings_model_name = require_env("OPENAI_EMBEDDINGS_DEPLOYMENT_MODEL")
    embeddings_dimensions = int(get_env_or_default("OPENAI_EMBEDDINGS_DIMENSIONS", "1536"))

    vector_field = MAIN_VECTOR_FIELD
    chunk_field = "chunk"
    title_field = "title"
    source_path_field = "source_path"
    semantic_configuration = "index-and-vectorize-semantic-configuration"
    vector_algorithm = "index-and-vectorize-algorithm"
    vector_profile = "index-and-vectorize-azureOpenAi-text-profile"
    vectorizer = "index-and-vectorize-azureOpenAi-text-vectorizer"

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

    table_index_payload = {
        "name": names["table_index"],
        "fields": [
            {"name": "id", "type": "Edm.String", "searchable": True, "filterable": False, "retrievable": True, "stored": True, "sortable": False, "facetable": False, "key": True, "analyzer": "keyword"},
            {"name": "parent_id", "type": "Edm.String", "searchable": False, "filterable": True, "retrievable": True, "stored": True, "sortable": False, "facetable": False},
            {"name": "document_name", "type": "Edm.String", "searchable": True, "filterable": True, "retrievable": True, "stored": True, "sortable": False, "facetable": True},
            {"name": "source_path", "type": "Edm.String", "searchable": False, "filterable": True, "retrievable": True, "stored": True, "sortable": False, "facetable": False},
            {"name": "page", "type": "Edm.Int32", "searchable": False, "filterable": True, "retrievable": True, "stored": True, "sortable": True, "facetable": True},
            {"name": "section", "type": "Edm.String", "searchable": True, "filterable": True, "retrievable": True, "stored": True, "sortable": False, "facetable": True},
            {"name": "table_title", "type": "Edm.String", "searchable": True, "filterable": True, "retrievable": True, "stored": True, "sortable": False, "facetable": True},
            {"name": "row_kind", "type": "Edm.String", "searchable": False, "filterable": True, "retrievable": True, "stored": True, "sortable": False, "facetable": True},
            {"name": "line_number", "type": "Edm.String", "searchable": True, "filterable": True, "retrievable": True, "stored": True, "sortable": True, "facetable": False},
            {"name": "item", "type": "Edm.String", "searchable": True, "filterable": False, "retrievable": True, "stored": True, "sortable": False, "facetable": False},
            {"name": "category", "type": "Edm.String", "searchable": True, "filterable": True, "retrievable": True, "stored": True, "sortable": False, "facetable": True},
            {"name": "request_amount", "type": "Edm.Int64", "searchable": False, "filterable": True, "retrievable": True, "stored": True, "sortable": True, "facetable": True},
            {"name": "authorized_amount", "type": "Edm.Int64", "searchable": False, "filterable": True, "retrievable": True, "stored": True, "sortable": True, "facetable": True},
            {"name": "delta_amount", "type": "Edm.Int64", "searchable": False, "filterable": True, "retrievable": True, "stored": True, "sortable": True, "facetable": True},
            {"name": "adjustment_reason", "type": "Edm.String", "searchable": True, "filterable": False, "retrievable": True, "stored": True, "sortable": False, "facetable": False},
            {"name": "content", "type": "Edm.String", "searchable": True, "filterable": False, "retrievable": True, "stored": True, "sortable": False, "facetable": False},
            {"name": "raw_text", "type": "Edm.String", "searchable": True, "filterable": False, "retrievable": True, "stored": True, "sortable": False, "facetable": False},
            {"name": "columns_json", "type": "Edm.String", "searchable": False, "filterable": False, "retrievable": True, "stored": True, "sortable": False, "facetable": False},
            {
                "name": TABLE_ROW_VECTOR_FIELD,
                "type": "Collection(Edm.Single)",
                "searchable": True,
                "filterable": False,
                "retrievable": True,
                "stored": True,
                "sortable": False,
                "facetable": False,
                "dimensions": embeddings_dimensions,
                "vectorSearchProfile": vector_profile,
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
                        "titleField": {"fieldName": "item"},
                        "prioritizedContentFields": [{"fieldName": "content"}, {"fieldName": "raw_text"}],
                        "prioritizedKeywordsFields": [{"fieldName": "section"}, {"fieldName": "category"}],
                    },
                }
            ],
        },
        "vectorSearch": index_payload["vectorSearch"],
    }

    existing_table_index = await search_json("GET", f"/indexes('{names['table_index']}')?api-version=2026-04-01", admin_key)
    existing_id_field = next((field for field in (existing_table_index or {}).get("fields", []) if field.get("name") == "id"), None)
    if existing_id_field and (not existing_id_field.get("searchable") or existing_id_field.get("analyzer") != "keyword"):
        await search_request("DELETE", f"/indexes('{names['table_index']}')?api-version=2026-04-01", admin_key)
        logger.info("Deleted Search table row index %s to update key analyzer", names["table_index"])

    await search_request("PUT", f"/indexes('{names['table_index']}')?api-version=2026-04-01", admin_key, table_index_payload)
    logger.info("Configured Search table row index %s", names["table_index"])


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


def _make_search_client(index_name: str, credential: ChainedTokenCredential) -> SearchClient:
    endpoint = require_env("SEARCH_SERVICE_ENDPOINT")
    admin_key = get_search_admin_key()
    if admin_key:
        return SearchClient(endpoint=endpoint, index_name=index_name, credential=AzureKeyCredential(admin_key))
    return SearchClient(endpoint=endpoint, index_name=index_name, credential=credential, audience=get_search_audience())


def _batch_by_char_budget(texts: list[str]) -> Iterable[list[str]]:
    batch: list[str] = []
    budget = 0
    for text in texts:
        clipped = text[:EMBED_MAX_INPUT_CHARS]
        if batch and budget + len(clipped) > MAX_EMBED_REQUEST_CHARS:
            yield batch
            batch, budget = [], 0
        batch.append(clipped)
        budget += len(clipped)
    if batch:
        yield batch


def _openai_client(credential: ChainedTokenCredential) -> AsyncAzureOpenAI:
    token_provider = get_bearer_token_provider(credential, f"{get_cognitive_services_audience()}/.default")
    return AsyncAzureOpenAI(
        azure_endpoint=require_env("OPENAI_ACCOUNT_ENDPOINT"),
        api_version=get_env_or_default("OPENAI_EMBEDDINGS_API_VERSION", "2023-05-15"),
        azure_ad_token_provider=token_provider,
    )


async def _embed_texts(client: AsyncAzureOpenAI, deployment: str, texts: list[str]) -> list[list[float]]:
    vectors: list[list[float]] = []
    for batch in _batch_by_char_budget(texts):
        response = await client.embeddings.create(model=deployment, input=batch)
        vectors.extend(item.embedding for item in sorted(response.data, key=lambda entry: entry.index))
    if len(vectors) != len(texts):
        raise RuntimeError(f"Embedding count mismatch: got {len(vectors)} vectors for {len(texts)} inputs")
    return vectors


async def _upload_documents(
    index_name: str,
    documents: list[TableRowDocument | MainPageDocument],
    credential: ChainedTokenCredential,
    label: str,
    vector_field: str,
) -> int:
    if not documents:
        logger.info("No %s to upload to %s", label, index_name)
        return 0

    deployment = require_env("OPENAI_EMBEDDINGS_DEPLOYMENT_NAME")
    async with _make_search_client(index_name, credential) as search_client, _openai_client(credential) as openai_client:
        for batch_start in range(0, len(documents), BATCH_SIZE):
            batch = documents[batch_start : batch_start + BATCH_SIZE]
            vectors = await _embed_texts(openai_client, deployment, [doc.embedding_source for doc in batch])
            payload = []
            for doc, vector in zip(batch, vectors):
                record = doc.as_search_document()
                record[vector_field] = vector
                payload.append(record)
            result = await search_client.merge_or_upload_documents(payload)
            failed = [item for item in result if not item.succeeded]
            if failed:
                raise RuntimeError(f"Failed to upload {len(failed)} {label} to {index_name}")
            logger.info("Embedded and uploaded %s/%s %s", min(batch_start + BATCH_SIZE, len(documents)), len(documents), label)

    logger.info("Uploaded %s %s to %s", len(documents), label, index_name)
    return len(documents)


async def _clear_index(index_name: str, key_field: str, credential: ChainedTokenCredential, label: str) -> int:
    deleted_count = 0
    async with _make_search_client(index_name, credential) as search_client:
        for _ in range(1000):
            document_keys: list[dict[str, str]] = []
            results = await search_client.search("*", select=[key_field], top=1000)
            async for result in results:
                key_value = result.get(key_field)
                if key_value:
                    document_keys.append({key_field: key_value})
            if not document_keys:
                break
            for batch_start in range(0, len(document_keys), BATCH_SIZE):
                await search_client.delete_documents(document_keys[batch_start : batch_start + BATCH_SIZE])
                deleted_count += len(document_keys[batch_start : batch_start + BATCH_SIZE])

    if deleted_count:
        logger.info("Deleted %s stale %s from %s", deleted_count, label, index_name)
    return deleted_count


async def main() -> None:
    parser = argparse.ArgumentParser(description="Upload docs and configure Azure AI Search for the MCP server.")
    parser.add_argument(
        "--configure-only",
        action="store_true",
        help="Only create/update the Azure AI Search indexes. Do not extract PDFs or upload documents.",
    )
    args = parser.parse_args()

    load_azd_environment()
    credential = ChainedTokenCredential(AzureCliCredential(), ManagedIdentityCredential())
    async with credential:
        if args.configure_only:
            await configure_search()
            logger.info("Configured Azure AI Search objects; skipping document upload and indexer run")
            return

        uploaded_count = await upload_docs(credential)
        page_count = 0
        table_row_count = 0
        try:
            await configure_search()
            names = get_search_resource_names()
            page_documents, table_rows = await extract_pdf_content(credential)
            await _clear_index(names["index"], "chunk_id", credential, "full-text page(s)")
            page_count = await _upload_documents(names["index"], page_documents, credential, "full-text page(s)", MAIN_VECTOR_FIELD)
            await _clear_index(names["table_index"], "id", credential, "table row(s)")
            table_row_count = await _upload_documents(names["table_index"], table_rows, credential, "table row(s)", TABLE_ROW_VECTOR_FIELD)
            logger.info(
                "Seeded %s file(s), %s full-text page(s), and %s table row(s) directly into Azure AI Search",
                uploaded_count,
                page_count,
                table_row_count,
            )
        except (aiohttp.ClientError, asyncio.TimeoutError) as exc:
            logger.warning(
                "Uploaded docs, but could not reach the Azure AI Search data-plane endpoint to configure Search or upload content: %s",
                exc,
            )
            logger.warning("Rerun `uv run python scripts/seed_search.py` from a network that can reach SEARCH_SERVICE_ENDPOINT.")
            logger.info("Seeded %s file(s) so far from %s", uploaded_count, DOCS_DIR)


if __name__ == "__main__":
    asyncio.run(main())