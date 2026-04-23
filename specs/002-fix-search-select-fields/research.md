# Research: Fix Search Select Fields Mismatch

**Date**: 2026-04-23

## Schema Introspection via SearchIndexClient

### Decision: Use `SearchIndexClient.get_index()` at server startup

**Rationale**: The `azure-search-documents` SDK (already a dependency) provides `SearchIndexClient` in `azure.search.documents.indexes`. Calling `get_index(index_name)` returns a `SearchIndex` object with:

- `fields: List[SearchField]` — each field has:
  - `name: str` — field name
  - `type: str` — e.g. `Edm.String`, `Collection(Edm.Single)`
  - `hidden: bool` — `True` means not retrievable (not suitable for `$select`)
  - `vector_search_dimensions: int | None` — set for vector fields
  - `vector_search_profile_name: str | None` — set for vector fields
- `semantic_search: SemanticSearch` — has:
  - `default_configuration_name: str | None`
  - `configurations: List[SemanticConfiguration]` — each has `name: str`

**Alternatives considered**:
1. *Hardcode both schemas* — fragile, breaks when a third schema is introduced
2. *Try/catch on each field* — N+1 requests, poor performance
3. *Schema introspection on first tool call* — works but adds latency to first request; user asked for server startup

### Field Classification Logic

A field is a **vector field** if `vector_search_dimensions is not None` or `vector_search_profile_name is not None`.

A field is **selectable** (for `$select`) if:
- It is NOT a vector field
- `hidden` is not `True`
- `type` is not `ComplexType` (complex types can cause issues in `$select`)

### Semantic Configuration Discovery

Use `semantic_search.default_configuration_name` if set. Otherwise use first configuration from `semantic_search.configurations`.

### SearchIndexClient Construction

`SearchIndexClient` requires the same `endpoint`, `credential`, and `audience` as `SearchClient`. Reuse the existing `_build_default_credential()` and cloud-aware audience logic from `_get_search_client()`.

### Caching Strategy

Use `@lru_cache(maxsize=1)` on the introspection function, same pattern as `_get_search_client()`. Cache is per-process lifetime, invalidated only on restart.

### Loading at Server Startup

The user wants the schema loaded at server start rather than lazily on first tool call. This means calling the introspection after `_load_environment()` during module initialization (before FastMCP starts accepting requests). This eliminates first-request latency and surfaces configuration errors early.

### Env Overrides

- `SEARCH_SELECT_FIELDS` (comma-separated) → override discovered select fields
- `SEARCH_VECTOR_FIELD_NAME` → override discovered vector field
- `SEARCH_SEMANTIC_CONFIGURATION_NAME` → already exists as env override in `_get_semantic_configuration_candidates()`

## No New Dependencies

`SearchIndexClient` lives in `azure.search.documents.indexes` — same package already installed (`azure-search-documents`). No changes to `requirements.txt` or `pyproject.toml`.
