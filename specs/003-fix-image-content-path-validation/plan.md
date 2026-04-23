# Implementation Plan: Fix Image Content Path Validation

**Branch**: `003-fix-image-content-path-validation` | **Date**: 2026-04-23 | **Spec**: [specs/003-fix-image-content-path-validation/spec.md](../003-fix-image-content-path-validation/spec.md)
**Input**: Feature specification from `specs/003-fix-image-content-path-validation/spec.md`

## Summary

The `get_image_from_content_path` MCP tool fails in production because AI agents construct invalid image paths from search results that don't contain image content. The root cause is twofold:

1. **Prompt/tool description issue (primary)**: The `get_image_from_content_path` tool description is insufficiently specific. It says "use content paths returned by semantic_search" but doesn't explain that the AI agent must look for an explicit `content_path` field in the search results. When the index has no such field (e.g., the Bicep-provisioned text-only index), the AI agent hallucinates a URL by decoding the base64 `parent_id` field and passes a source document PDF URL.

2. **Validation strictness (secondary)**: `_is_likely_image_content_path()` uses an allowlist (must end in image extension) which is correct for rejecting the PDF but would also reject valid extensionless image paths that future index schemas might produce.

The fix improves tool descriptions to prevent AI agents from calling `get_image_from_content_path` when no image content exists in search results, switches validation from allowlist to denylist for resilience, improves error messages to guide agent self-correction, and **ensures `_download_blob_image` strips full URL prefixes** if the LLM prepends one. The image container (`multimodal-rag-images`) is embedded in the `content_path` and differs from `STORAGE_ACCOUNT_CONTAINER_NAME`, so container extraction from the path is preserved.

## Technical Context

**Language/Version**: Python >= 3.10  
**Primary Dependencies**: FastMCP >= 2.x, azure-search-documents >= 11.x, azure-storage-blob >= 12.x, azure-identity >= 1.x  
**Storage**: Azure Blob Storage (images), Azure AI Search (index — may or may not have `content_path` field depending on schema)  
**Testing**: Manual validation against deployed search index; no test framework currently in use  
**Target Platform**: Azure App Service (Linux), Python 3.10+  
**Project Type**: MCP web service  
**Performance Goals**: N/A (bug fix, no performance-sensitive changes)  
**Constraints**: Must not break existing working paths; must remain compatible with both multimodal-RAG and Bicep-provisioned index schemas  
**Scale/Scope**: Single file change (`main.py`), ~40 lines modified across tool descriptions, validation logic, and path normalization

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Principle | Status | Notes |
|---|-----------|--------|-------|
| I | Infrastructure as Code | PASS | No infra changes required — bug is in application code only |
| II | Security by Default | PASS | Input validation is being improved (denylist for document extensions). No secrets or auth changes. Validation at MCP tool boundary is maintained per constitution §Security Requirements |
| III | Cloud Portability | PASS | No cloud-specific URLs or constants introduced. Existing `_is_likely_image_content_path` is cloud-agnostic and will remain so |
| IV | MCP Protocol Compliance | PASS | Tool continues to accept typed parameters, return structured Image content, and provide meaningful error messages |
| V | Observability | PASS | Existing logging for rejected/accepted paths is preserved. Warning log on rejection remains |

**Gate Result**: ALL PASS — proceed to Phase 0

## Project Structure

### Documentation (this feature)

```text
specs/003-fix-image-content-path-validation/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
main.py                  # Single-file MCP server — all changes here
image_return_example.json # Reference: example search result with content_path field
```

**Structure Decision**: Single-file project. All changes are in `main.py`. No new files or modules needed.

## Complexity Tracking

No constitution violations — table not required.

## Post-Design Constitution Re-Check

| # | Principle | Status | Notes |
|---|-----------|--------|-------|
| I | Infrastructure as Code | PASS | No infra changes in design |
| II | Security by Default | PASS | Input validation improved: denylist rejects known document types at MCP boundary. Tool description hardened to prevent agents from constructing arbitrary URLs |
| III | Cloud Portability | PASS | No cloud-specific constants introduced. URL parsing handles all cloud endpoints |
| IV | MCP Protocol Compliance | PASS | Tool description improved per MCP best practices — clearer parameter guidance, better error messages. Signature unchanged |
| V | Observability | PASS | Existing `logger.warning` for rejected paths preserved. Error messages improved for diagnosability |

**Post-Design Gate Result**: ALL PASS

## Generated Artifacts

| Artifact | Path |
|----------|------|
| Research | `specs/003-fix-image-content-path-validation/research.md` |
| Data Model | `specs/003-fix-image-content-path-validation/data-model.md` |
| Quickstart | `specs/003-fix-image-content-path-validation/quickstart.md` |

## Next Step

Run `/speckit.tasks` to generate the implementation task list.
