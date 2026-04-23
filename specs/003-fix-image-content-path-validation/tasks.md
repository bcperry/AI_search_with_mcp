# Tasks: Fix Image Content Path Validation

**Input**: Design documents from `specs/003-fix-image-content-path-validation/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

**Tests**: Not requested in the feature specification. No test tasks generated.

**Organization**: Tasks grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Add the new constant needed by all subsequent tasks

- [X] T001 Add `_NON_IMAGE_EXTENSIONS` denylist constant near existing `_IMAGE_EXTENSIONS` in main.py (line ~144)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Change the shared validation function — all user stories depend on this

**⚠️ CRITICAL**: The validation function is used by both the public tool and the internal helper. Must be updated before story-specific work.

- [X] T002 Rewrite `_is_likely_image_content_path()` in main.py to use denylist (`_NON_IMAGE_EXTENSIONS`) instead of allowlist (`_IMAGE_EXTENSIONS`), returning `False` for known document extensions and `True` for everything else (including extensionless paths)

**Checkpoint**: Validation logic updated — user story implementation can begin

---

## Phase 3: User Story 1 — Retrieve Image via Valid Blob-Relative Content Path (Priority: P1) 🎯 MVP

**Goal**: Ensure the tool accepts valid `content_path` values from the multimodal-RAG search index and downloads images successfully

**Independent Test**: Call `get_image_from_content_path` with a blob-relative path like `multimodal-rag-images/<base64-path>/normalized_images_1.jpg` and verify the image is returned

### Implementation for User Story 1

- [X] T003 [US1] Rewrite `get_image_from_content_path` docstring in main.py to explicitly state: only call when search results contain a `content_path` field; never construct URLs from `parent_id`, `title`, or other fields; pass the `content_path` value verbatim; if results lack `content_path`, no images are available
- [X] T004 [US1] Update the `ValueError` message in `get_image_from_content_path` in main.py (line ~660) to mention the specific document extension that caused rejection and explain that the tool requires a `content_path` field from search results containing image content

**Checkpoint**: User Story 1 complete — valid blob-relative paths accepted, improved tool description prevents misuse

---

## Phase 4: User Story 2 — Retrieve Image via Full Blob Storage URL (Priority: P1)

**Goal**: If the LLM prepends a full blob URL to the content_path, the server normalizes it before container extraction

**Independent Test**: Call `get_image_from_content_path` with `https://account.blob.core.usgovcloudapi.net/multimodal-rag-images/<base64-path>/normalized_images_1.jpg` and verify the image is returned

### Implementation for User Story 2

- [X] T005 [US2] Verify and ensure `_download_blob_image` in main.py already strips full blob URL prefix (scheme + host) via its existing `urlparse` logic before splitting on `/` for container extraction — add a log message at DEBUG level when URL prefix stripping occurs

**Checkpoint**: Full blob URLs handled — server normalizes them to relative paths before container extraction

---

## Phase 5: User Story 3 — Reject Clearly Non-Image Paths with Helpful Error (Priority: P2)

**Goal**: Document paths like `.pdf`, `.docx` are rejected with actionable error messages

**Independent Test**: Call `get_image_from_content_path` with a `.pdf` URL and verify a `ValueError` is raised with the improved message

### Implementation for User Story 3

- [X] T006 [US3] Verify the updated `_is_likely_image_content_path()` (from T002) correctly rejects all extensions in `_NON_IMAGE_EXTENSIONS` and update the rejection log message in `_download_blob_image` in main.py (line ~349) to include the detected extension

**Checkpoint**: Non-image paths rejected with clear, actionable error messages

---

## Phase 6: User Story 4 — Accept Content Paths Without File Extensions (Priority: P2)

**Goal**: Extensionless paths are accepted and download is attempted

**Independent Test**: Call `get_image_from_content_path` with a path like `multimodal-rag-images/<base64-path>/normalized_images_1` (no extension) and verify the download is attempted

### Implementation for User Story 4

- [X] T007 [US4] Verify the updated `_is_likely_image_content_path()` (from T002) returns `True` for extensionless paths — no additional code changes expected since denylist approach inherently accepts them

**Checkpoint**: Extensionless paths accepted — download attempted rather than rejected

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final validation across all scenarios

- [X] T008 Run quickstart.md validation — deploy updated main.py and verify end-to-end: (1) text-only index: agent does not call `get_image_from_content_path`, (2) multimodal-RAG index: agent calls tool with `content_path` and image is returned, (3) PDF URL passed: clear error message

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — add constant first
- **Foundational (Phase 2)**: Depends on Phase 1 — rewrite validation function
- **User Stories (Phases 3–6)**: All depend on Phase 2 completion
  - US1 (Phase 3) and US2 (Phase 4) are P1 and can proceed in parallel
  - US3 (Phase 5) and US4 (Phase 6) are P2 and can proceed in parallel
  - All four stories can run in parallel since they touch different parts of main.py
- **Polish (Phase 7)**: Depends on all user stories being complete

### Within Each User Story

- Tool description (T003) and error message (T004) are independent — can be parallel
- URL normalization verification (T005) is independent
- Denylist verification (T006, T007) depends on T002

### Parallel Opportunities

```text
After T002 completes:
  ├── T003 [US1] Tool description rewrite
  ├── T004 [US1] Error message update
  ├── T005 [US2] URL prefix stripping verification
  ├── T006 [US3] Denylist rejection verification
  └── T007 [US4] Extensionless path verification
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Add `_NON_IMAGE_EXTENSIONS` constant (T001)
2. Complete Phase 2: Rewrite validation function (T002)
3. Complete Phase 3: Tool description + error message (T003, T004)
4. **STOP and VALIDATE**: Deploy and test with both index types
5. Proceed to remaining stories if needed

### All Changes Summary

All changes are in a single file: `main.py`
- **~Line 144**: Add `_NON_IMAGE_EXTENSIONS` constant
- **~Line 275**: Rewrite `_is_likely_image_content_path()` function
- **~Line 349**: Update rejection log message in `_download_blob_image`
- **~Line 636**: Rewrite `get_image_from_content_path` docstring
- **~Line 660**: Update `ValueError` message

Total: 8 tasks, ~40 lines of changes in 1 file
