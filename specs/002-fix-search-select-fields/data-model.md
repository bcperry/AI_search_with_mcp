# Data Model: Fix Search Select Fields Mismatch

**Date**: 2026-04-23

## IndexSchema (cached in-memory dataclass or named tuple)

Represents the introspected schema of the active search index, cached for process lifetime.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `select_fields` | `List[str]` | Non-vector, retrievable field names for `$select` |
| `vector_field_name` | `str` | Name of the first vector field (e.g. `text_vector` or `content_embedding`) |
| `semantic_configuration_name` | `Optional[str]` | Default semantic configuration name, or first available |

### Discovery Logic

```
For each field in index.fields:
    if field.vector_search_dimensions or field.vector_search_profile_name:
        → vector field (use first as vector_field_name)
    elif not field.hidden and field.type != ComplexType:
        → add to select_fields
```

### Env Overrides (highest priority)

| Variable | Override Target | Format |
|----------|----------------|--------|
| `SEARCH_SELECT_FIELDS` | `select_fields` | Comma-separated field names |
| `SEARCH_VECTOR_FIELD_NAME` | `vector_field_name` | Single field name |
| `SEARCH_SEMANTIC_CONFIGURATION_NAME` | `semantic_configuration_name` | Single name |

### State Transitions

None — the schema is read-only after discovery and cached for process lifetime.

## Impact on Existing Code

| Current Code | Change |
|---|---|
| `_SEARCH_SELECT_FIELDS` (module-level list) | Replaced by `schema.select_fields` |
| `_VECTOR_FIELD_CANDIDATES` (module-level list) | Replaced by `schema.vector_field_name` (single value) |
| `_get_semantic_configuration_candidates()` | Simplified — use `schema.semantic_configuration_name` directly |
| `semantic_search()` retry loops over field/config combos | Eliminated — single known-good field and config |
