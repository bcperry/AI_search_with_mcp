# Tasks: Fix Search Select Fields Mismatch

**Input**: Design documents from `/specs/002-fix-search-select-fields/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, quickstart.md

**Tests**: Not requested in spec — test tasks omitted.

**Organization**: This is a single-file bugfix. Tasks grouped by user story: US1 (schema introspection), US2 (simplify semantic_search to use discovered schema).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Exact file paths included in descriptions

---

## Phase 1: Setup

**Purpose**: Add the import needed for schema introspection. No new dependencies.

- [x] T001 Add `from azure.search.documents.indexes import SearchIndexClient` import to main.py

**Checkpoint**: Import available. No new packages required — `SearchIndexClient` is in the existing `azure-search-documents` package.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build the `_get_index_schema()` function that introspects the search index and caches the result. All subsequent tasks depend on this.

**⚠️ CRITICAL**: Must complete before US1/US2 tasks can use the discovered schema.

- [x] T002 Create `_get_search_index_client()` function in main.py that constructs a `SearchIndexClient` using the same cloud-aware `endpoint`, `credential`, and `audience` logic as the existing `_get_search_client()` function. Decorate with `@lru_cache(maxsize=1)`.
- [x] T003 Create `_get_index_schema()` function in main.py that calls `_get_search_index_client().get_index(index_name)` and returns a named tuple or dataclass `IndexSchema(select_fields, vector_field_name, semantic_configuration_name)`. Classification logic: vector fields have `vector_search_dimensions is not None` or `vector_search_profile_name is not None`; select fields are non-vector, non-hidden, non-ComplexType retrievable fields. For semantic config: use `index.semantic_search.default_configuration_name` if set, else first config from `index.semantic_search.configurations`. Decorate with `@lru_cache(maxsize=1)`. Log discovered fields at INFO level.
- [x] T004 Add env override logic inside `_get_index_schema()` in main.py: if `SEARCH_SELECT_FIELDS` env var is set (comma-separated), use it instead of discovered select fields; if `SEARCH_VECTOR_FIELD_NAME` is set, use it instead of discovered vector field; if `SEARCH_SEMANTIC_CONFIGURATION_NAME` is set, use it instead of discovered semantic config.
- [x] T005 Add fallback error handling to `_get_index_schema()` in main.py: if `SearchIndexClient.get_index()` raises an exception, log a WARNING and return `IndexSchema(select_fields=[], vector_field_name="text_vector", semantic_configuration_name=None)` so the search can still be attempted without `$select`.

**Checkpoint**: `_get_index_schema()` returns correct `IndexSchema` for any index schema, with env overrides and graceful fallback.

---

## Phase 3: User Story 1 — Remove Hardcoded Field Lists (Priority: P1) 🎯 MVP

**Goal**: Replace the hardcoded `_SEARCH_SELECT_FIELDS`, `_VECTOR_FIELD_CANDIDATES`, and `_get_semantic_configuration_candidates()` with the dynamically discovered `IndexSchema`.

**Independent Test**: Start server pointed at Bicep-provisioned index → no `content_id` error. Start server pointed at multimodal-RAG index → fields discovered correctly. Check startup logs for discovered field names.

### Implementation for User Story 1

- [x] T006 [US1] Remove the `_SEARCH_SELECT_FIELDS` module-level list from main.py (lines ~141-148)
- [x] T007 [US1] Remove the `_VECTOR_FIELD_CANDIDATES` module-level list from main.py (line ~149)
- [x] T008 [US1] Remove the `_get_semantic_configuration_candidates()` function from main.py (lines ~207-222)

**Checkpoint**: Hardcoded field lists and semantic config candidates function are removed.

---

## Phase 4: User Story 2 — Update semantic_search() to Use IndexSchema (Priority: P1)

**Goal**: Rewrite the `semantic_search()` tool to use `_get_index_schema()` instead of the removed hardcoded lists. Eliminate the retry loops over multiple field/config combinations.

**Independent Test**: Call `semantic_search` tool with a query → returns results. Startup logs show discovered fields. No `$select` errors.

### Implementation for User Story 2

- [x] T009 [US2] Update `semantic_search()` in main.py to call `schema = _get_index_schema()` at the start of the function, replacing references to `_SEARCH_SELECT_FIELDS` with `schema.select_fields`, and use `schema.vector_field_name` instead of iterating `_VECTOR_FIELD_CANDIDATES`
- [x] T010 [US2] Update the `_run()` inner function in `semantic_search()` in main.py: pass `schema.select_fields` to the `select` parameter (or omit `select` entirely if `schema.select_fields` is empty for graceful fallback), use `schema.vector_field_name` for `VectorizableTextQuery.fields`, and use `schema.semantic_configuration_name` for `semantic_configuration_name`
- [x] T011 [US2] Simplify the retry loop in `semantic_search()` in main.py: remove the nested `for` loops over `semantic_configuration_candidates` and `_VECTOR_FIELD_CANDIDATES` since we now have a single known-good vector field and semantic config. Keep the `HttpResponseError` handling for unknown field errors but remove the multi-combination fallback logic.
- [x] T012 [US2] Update the response metadata in `semantic_search()` in main.py: replace hardcoded `_SEARCH_SELECT_FIELDS` references in `@search.nextPageParameters` with `schema.select_fields`, and replace hardcoded vector field name with `schema.vector_field_name`

**Checkpoint**: `semantic_search()` uses dynamically discovered schema. No retry loops over field combinations.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Startup invocation, validation, and cleanup.

- [x] T013 Add a call to `_get_index_schema()` during module initialization in main.py (after `_load_environment()` and before `mcp = FastMCP(...)`) so schema is loaded at server startup and errors surface early
- [x] T014 [P] Clean up the `_extract_unknown_field_name()` function in main.py: verify it still works correctly with the simplified error handling (no changes expected, just confirm it's still referenced)
- [x] T015 [P] Verify startup logs match the quickstart.md expected format: `Introspected index '...': select_fields=[...], vector_field='...', semantic_config='...'`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (import)
- **User Story 1 (Phase 3)**: Depends on Phase 2 (schema function must exist before removing old lists)
- **User Story 2 (Phase 4)**: Depends on Phase 2 + Phase 3 (schema function exists, old lists removed)
- **Polish (Phase 5)**: Depends on Phase 4 (semantic_search uses schema)

### User Story Dependencies

- **User Story 1 (P1)**: Depends on Foundational only — removes old code
- **User Story 2 (P1)**: Depends on Foundational + US1 — rewrites semantic_search

### Within User Story 2

- T009 before T010 (get schema reference before using it in `_run()`)
- T010 before T011 (update `_run()` before simplifying retry loop)
- T011 before T012 (simplify loop before fixing response metadata)

### Parallel Opportunities

- T014, T015 (independent validation checks)
- T006, T007, T008 (removing independent code blocks — same file but non-overlapping)

---

## Implementation Strategy

### MVP First (User Story 1 + User Story 2)

1. Complete Phase 1: Add import
2. Complete Phase 2: Build `_get_index_schema()` with caching, env overrides, fallback
3. Complete Phase 3: Remove hardcoded lists
4. Complete Phase 4: Update `semantic_search()` to use `IndexSchema`
5. **STOP and VALIDATE**: Start server, check logs, test `semantic_search`
6. Complete Phase 5: Startup call, cleanup

### Incremental Delivery

1. Setup + Foundational → Schema introspection ready
2. US1 → Hardcoded lists removed
3. US2 → `semantic_search()` rewired → **Deploy (MVP!)**
4. Polish → Startup validation, log format check

---

## Notes

- Total tasks: 15
- User Story 1 (remove hardcoded): 3 tasks (T006–T008)
- User Story 2 (rewire semantic_search): 4 tasks (T009–T012)
- All changes in single file: main.py
- No new dependencies, no `requirements.txt` changes
- Parallel opportunities: T006/T007/T008 (removals), T014/T015 (validation)
- Suggested MVP scope: All phases (small bugfix, all phases needed for correctness)
- Format validation: ALL tasks follow `- [ ] [ID] [labels] description with file path` format ✅
