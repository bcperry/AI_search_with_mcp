# Quickstart: Fix Image Content Path Validation

**Feature**: 003-fix-image-content-path-validation  
**Date**: 2026-04-23

## What Changed

Three fixes to prevent AI agents from incorrectly calling `get_image_from_content_path`:

1. **Tool description rewrite (primary fix)**: The `get_image_from_content_path` docstring now explicitly tells AI agents to only call it when search results contain a `content_path` field, and to never construct URLs from other fields like `parent_id` or `title`.

2. **Server-side path normalization (defense in depth)**: `_download_blob_image` now strips full blob URL prefixes before extracting the container. The image container (`multimodal-rag-images`) is embedded in the `content_path` and differs from `STORAGE_ACCOUNT_CONTAINER_NAME`, so it must come from the path itself.

3. **Validation logic switch (secondary)**: `_is_likely_image_content_path()` changed from an allowlist (must have image extension) to a denylist (reject known document extensions like `.pdf`, `.docx`). Accepts extensionless paths and unknown formats.

## Changes At a Glance

| File | Change |
|------|--------|
| `main.py` | Add `_NON_IMAGE_EXTENSIONS` constant (~line 144) |
| `main.py` | Rewrite `_is_likely_image_content_path()` to use denylist |
| `main.py` | Rewrite `get_image_from_content_path` docstring to be explicit about when to call |
| `main.py` | Simplify `_download_blob_image` URL prefix stripping (keep container extraction from path) |
| `main.py` | Improve error message for rejected paths |

## Before / After

### Tool Description — Before
```python
"""Download an image from Azure Blob Storage and return MCP Image content.

As a general rule, use this tool only with content paths returned by
semantic_search, not arbitrary source document paths.
...
```

### Tool Description — After
```python
"""Download an image from Azure Blob Storage and return MCP Image content.

IMPORTANT: Only call this tool when semantic_search results contain an explicit
'content_path' field in a result hit. If search results do NOT include a
'content_path' field, there are no images available to retrieve — do not call
this tool. Never construct a URL from parent_id, title, chunk_id, or other
fields; only use the literal content_path value from a search result.
...
```

### Validation — Before
```python
_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ...}

def _is_likely_image_content_path(value):
    suffix = Path(path_value).suffix.lower()
    return suffix in _IMAGE_EXTENSIONS  # ALLOWLIST
```

### Validation — After
```python
_NON_IMAGE_EXTENSIONS = {".pdf", ".docx", ".doc", ".xlsx", ".xls",
                         ".pptx", ".ppt", ".txt", ".csv", ".html", ".htm"}

def _is_likely_image_content_path(value):
    suffix = Path(path_value).suffix.lower()
    if suffix in _NON_IMAGE_EXTENSIONS:
        return False  # DENYLIST — reject known documents
    return True  # Accept everything else
```

## How to Verify

1. Deploy the updated `main.py`
2. Connect to the text-only index (`index-and-vectorize`)
3. Ask the AI agent a question about images/diagrams
4. Verify the agent does NOT call `get_image_from_content_path` (because search results have no `content_path` field)
5. If the agent does call the tool with a document URL, verify the improved error message guides correction

### Positive test (multimodal-RAG index)
- Run `semantic_search` → results include `content_path` → agent calls `get_image_from_content_path` → image returned

### Negative test
- Call `get_image_from_content_path` with a `.pdf` URL → should raise `ValueError` with improved message
