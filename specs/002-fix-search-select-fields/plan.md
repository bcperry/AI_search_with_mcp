# Implementation Plan: Fix Search Select Fields Mismatch

**Branch**: `002-fix-search-select-fields` | **Date**: 2026-04-23 | **Spec**: [spec.md](specs/002-fix-search-select-fields/spec.md)
**Input**: Feature specification from `/specs/002-fix-search-select-fields/spec.md`

## Summary

The `semantic_search` MCP tool fails when pointed at the Bicep-provisioned index because `_SEARCH_SELECT_FIELDS`, `_VECTOR_FIELD_CANDIDATES`, and semantic configuration names are hardcoded for the multimodal-RAG schema only. Fix by dynamically introspecting the index schema via `SearchIndexClient.get_index()` at first use, caching the result, and using discovered field names for `$select`, vector queries, and semantic configuration.

## Technical Context

**Language/Version**: Python >= 3.10 (per pyproject.toml)  
**Primary Dependencies**: FastMCP >= 2.x, azure-search-documents >= 11.x (already has `SearchIndexClient`)  
**Storage**: N/A (stateless — index schema cached in memory)  
**Testing**: Manual validation against both index schemas  
**Target Platform**: Azure App Service (Linux), local development  
**Project Type**: Web service (MCP server via streamable HTTP)  
**Performance Goals**: Single REST call to introspect index schema, cached for process lifetime  
**Constraints**: Must work with both multimodal-RAG and Bicep-provisioned index schemas; must support Azure Government  
**Scale/Scope**: Single file change (`main.py`); ~50 lines modified

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Infrastructure as Code | PASS | No infrastructure changes. Bug is in application code only. |
| II. Security by Default | PASS | `SearchIndexClient` uses the same `ChainedTokenCredential` already in use. No new secrets or credentials. |
| III. Cloud Portability | PASS | `SearchIndexClient` constructor already receives cloud-appropriate `audience` and `credential`. No new cloud-specific logic needed. |
| IV. MCP Protocol Compliance | PASS | No changes to tool parameters or response structure. Fix makes the existing tool work correctly. |
| V. Observability | PASS | Will log discovered fields at INFO level. No reduction in observability. |

**Gate Result**: PASS — no violations.

### Post-Phase 1 Re-Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Infrastructure as Code | PASS | No infrastructure changes. |
| II. Security by Default | PASS | `SearchIndexClient` uses existing `ChainedTokenCredential`. No new secrets. No credential changes. |
| III. Cloud Portability | PASS | `SearchIndexClient` constructed with same cloud-aware `audience` and `authority_host` as `SearchClient`. |
| IV. MCP Protocol Compliance | PASS | Tool parameters and response structure unchanged. Fix makes existing tool work with any index schema. |
| V. Observability | PASS | Discovered fields logged at INFO on startup. Vector/select field names visible in logs. |
| Tech Stack Constraints | PASS | No new dependencies — `SearchIndexClient` is in `azure.search.documents.indexes` (same package). |
| Simplicity (Governance) | PASS | Replaces ~15 lines of hardcoded lists + retry loops with ~30 lines of schema introspection + caching. Net complexity is comparable. |

**Post-Design Gate Result**: PASS — no violations.

## Project Structure

### Documentation (this feature)

```text
specs/002-fix-search-select-fields/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
main.py                  # Modified — replace hardcoded field lists with dynamic schema introspection
```

**Structure Decision**: No new files. All changes are in `main.py` — replacing the three hardcoded lists (`_SEARCH_SELECT_FIELDS`, `_VECTOR_FIELD_CANDIDATES`, semantic config candidates) with cached dynamic discovery from `SearchIndexClient.get_index()`.

## Complexity Tracking

> No Constitution Check violations — table not required.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
