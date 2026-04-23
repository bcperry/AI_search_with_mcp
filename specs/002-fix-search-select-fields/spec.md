# Feature Specification: Fix Search Select Fields Mismatch

**Branch**: `002-fix-search-select-fields` | **Date**: 2026-04-23

## Overview

The `semantic_search` MCP tool fails at runtime because `_SEARCH_SELECT_FIELDS` in `main.py` references field names (`content_id`, `text_document_id`, `document_title`, `image_document_id`, `content_text`, `content_path`) that do not exist in the deployed Azure AI Search index. The index created by the Bicep IaC (`createSearchIndex.bicep`) defines fields: `chunk_id`, `parent_id`, `chunk`, `title`, `text_vector`. The tool must dynamically discover available fields from the index schema instead of relying on a hardcoded list.

## Error

```
HttpResponseError: () Invalid expression: Could not find a property named 'content_id' on type 'search.document'.
Parameter name: $select
```

This error cascades to a `RuntimeError` because `content_id` is in `_SEARCH_SELECT_FIELDS` and the code's retry logic treats missing select fields as fatal (line 571).

## Root Cause

The project has **two index schemas**:

| | Multimodal-RAG index (`multimodal-rag-*`) | Bicep-provisioned index (`index-and-vectorize`) |
|---|---|---|
| Key | `content_id` | `chunk_id` |
| Parent | `text_document_id` | `parent_id` |
| Title | `document_title` | `title` |
| Text | `content_text` | `chunk` |
| Vector | `content_embedding` (1536) | `text_vector` |
| Image ref | `image_document_id` | — |
| Path | `content_path` | — |
| Extra | `locationMetadata` (complex) | — |

1. `_SEARCH_SELECT_FIELDS` is hardcoded for the multimodal-RAG schema. When the server is pointed at the Bicep-provisioned index, none of these fields exist and the search request fails immediately.
2. `_VECTOR_FIELD_CANDIDATES` lists `content_embedding` first, which only exists in the multimodal-RAG index — the retry loop recovers by trying `text_vector`, but the `$select` failure on `content_id` is fatal before any vector field fallback can help.
3. The semantic configuration name also differs between schemas (`multimodal-rag-semantic-configuration` vs `index-and-vectorize-semantic-configuration`).

## Requirements

### Functional Requirements

1. **Dynamic Field Discovery**: Query the search index schema at startup (or on first use) to discover available non-vector, retrievable fields. Use these as the `$select` list instead of the hardcoded `_SEARCH_SELECT_FIELDS`.
2. **Vector Field Discovery**: Similarly discover the actual vector field name(s) from the index schema instead of guessing from `_VECTOR_FIELD_CANDIDATES`.
3. **Semantic Configuration Discovery**: Discover the default semantic configuration name from the index schema instead of guessing from a hardcoded list.
4. **Caching**: Cache the discovered schema to avoid repeated REST calls. Invalidate only on process restart.
5. **Fallback**: If schema introspection fails (e.g., permissions), fall back to attempting the search without `$select` (return all fields) and log a warning.
6. **Env Override**: Allow `SEARCH_SELECT_FIELDS` environment variable (comma-separated) to override discovered fields for advanced users.
7. **Env Override for Vector**: Allow `SEARCH_VECTOR_FIELD_NAME` environment variable to override the discovered vector field.

### Non-Functional Requirements

1. **Backward Compatibility**: Indexes with the old multimodal schema (if any exist) should still work — dynamic discovery handles both schemas.
2. **Performance**: Single REST call to get index schema, cached for process lifetime.
3. **Observability**: Log discovered fields at INFO level on first use.

### Out of Scope

- Changing the Bicep index schema
- Supporting multiple indexes simultaneously (existing limitation)
- Modifying the search query logic beyond field selection

## Dependencies

- `azure-search-documents` SDK (already present) — `SearchIndexClient` for schema introspection
- No new dependencies required
