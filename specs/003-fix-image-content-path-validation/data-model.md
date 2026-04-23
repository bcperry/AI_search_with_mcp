# Data Model: Fix Image Content Path Validation

**Feature**: 003-fix-image-content-path-validation  
**Date**: 2026-04-23

## Entities

### Modified Constants

#### `_NON_IMAGE_EXTENSIONS` (NEW)

A set of file extensions for known non-image document formats. Used by the denylist validation.

| Field | Type | Value |
|-------|------|-------|
| type | `set[str]` | `{".pdf", ".docx", ".doc", ".xlsx", ".xls", ".pptx", ".ppt", ".txt", ".csv", ".html", ".htm"}` |
| location | `main.py` module-level constant | Near existing `_IMAGE_EXTENSIONS` (line ~143) |

#### `_IMAGE_EXTENSIONS` (UNCHANGED)

Retained for use in image format detection within `_download_blob_image`. No longer used in path validation.

| Field | Type | Value |
|-------|------|-------|
| type | `set[str]` | `{".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".tif", ".tiff"}` |
| location | `main.py` line 143 | Unchanged |

### Modified Functions

#### `_is_likely_image_content_path(value: Optional[str]) -> bool`

**Before** (allowlist):
- Returns `True` only if the path's file extension is in `_IMAGE_EXTENSIONS`
- Rejects extensionless paths, paths with query parameters obscuring extension, and any unexpected format

**After** (denylist):
- Returns `False` if the path's file extension is in `_NON_IMAGE_EXTENSIONS`
- Returns `True` for all other non-empty paths (including extensionless paths)
- Continues to return `False` for empty/whitespace-only input

**Signature**: Unchanged  
**Call sites**: `_download_blob_image` (line 348), `get_image_from_content_path` (line 659)

#### `get_image_from_content_path` (TOOL DESCRIPTION + BEHAVIOR CHANGE — PRIMARY FIX)

**Before** (vague description, complex path handling):
```
As a general rule, use this tool only with content paths returned by
semantic_search, not arbitrary source document paths.
```

**After** (explicit description, server-side normalization):
The docstring must clearly state:
1. Only call this tool when a search result hit contains a `content_path` field
2. If search results do not include a `content_path` field, there are no images to retrieve
3. Do NOT construct URLs from `parent_id`, `title`, or other fields — only use the literal `content_path` value
4. Just pass the `content_path` value exactly as it appears in the search result

**Server-side normalization** (in `_download_blob_image`):
- If input is a full blob URL → strip scheme/host to get relative path, then use existing container extraction
- If input is a relative path like `multimodal-rag-images/<base64-path>/normalized_images_N.jpg` → use existing split logic (first segment = container, rest = blob name)
- The image container (`multimodal-rag-images`) is different from `STORAGE_ACCOUNT_CONTAINER_NAME` — container must come from the `content_path` itself

**Error message change**:
- Before: "does not look like an image path. Pass the image content_path from semantic_search"
- After: Mentions the document extension, states the tool requires a `content_path` field from search results, and notes that if results lack this field, no images are available

### Modified Functions (continued)

#### `_download_blob_image(content_path: str) -> Optional[Image]`

**Before**: Splits input on `/` to guess container vs blob name. Falls back to default container only when first segment isn't a valid container name.

**After**: Same container extraction logic (split on first `/`), but adds URL prefix stripping as a normalization step. If the LLM passes a full blob URL, the scheme/host is stripped before the existing split logic runs. The image container (`multimodal-rag-images`) comes from the `content_path` itself — NOT from `STORAGE_ACCOUNT_CONTAINER_NAME`.

### Unchanged Entities

- Image format detection logic — continues to default to `"jpeg"` for unknown extensions
- `semantic_search` — tool description unchanged (already returns whatever fields the index has)

## State Transitions

N/A — no stateful entities in this change.

## Validation Rules

| Rule | Location | Behavior |
|------|----------|----------|
| Empty/whitespace path | `get_image_from_content_path` | Raises `ValueError("content_path is required and cannot be empty")` |
| Known non-image extension | `_is_likely_image_content_path` | Returns `False` → tool raises `ValueError` with descriptive message mentioning the document extension |
| Image extension (`.jpg`, etc.) | `_is_likely_image_content_path` | Returns `True` → proceeds to download |
| No extension | `_is_likely_image_content_path` | Returns `True` → proceeds to download (may fail at blob level) |
| Unknown extension | `_is_likely_image_content_path` | Returns `True` → proceeds to download (may fail at blob level) |
