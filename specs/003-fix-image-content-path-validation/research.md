# Research: Fix Image Content Path Validation

**Feature**: 003-fix-image-content-path-validation  
**Date**: 2026-04-23

## Research Task 1: Root Cause Analysis — What Actually Happened

### Findings

From the `bug_context.txt` trace, the actual failure sequence was:

1. AI agent called `semantic_search` with query about "small unmanned aircraft system drone operations visual line of sight image or diagram"
2. Search hit the **Bicep-provisioned index** (`avcoe-demo-ai-search-mcp-index-and-vectorize`) which returns: `chunk_id`, `parent_id`, `chunk`, `title` — **NO `content_path` field**
3. All 3 results were **text-only chunks** from `.docx` and `.pdf` source documents — no image content
4. The AI agent **hallucinated** a blob URL by apparently decoding the base64 `parent_id` field, producing: `https://avcoedemoaisearchmcpstg.blob.core.windows.net/avcoe-demo-ai-search-mcp-container/011-WSH3001L%20%20Introduction%20to%20UAS%20(08%20May%2024).pdf`
5. The agent passed this PDF URL to `get_image_from_content_path`
6. `_is_likely_image_content_path()` correctly rejected `.pdf` → `ValueError`

**The validation was correct.** The `.pdf` URL is not an image. The bug is that the AI agent called the tool when it shouldn't have.

### Root Cause: Insufficiently specific tool descriptions

The `get_image_from_content_path` docstring says:
> "As a general rule, use this tool only with content paths returned by semantic_search, not arbitrary source document paths."

This is too vague. The AI agent interpreted "content paths returned by semantic_search" loosely and derived a path from the `parent_id` field rather than finding an actual `content_path` field in the results. The tool description needs to:
- Explicitly state that a `content_path` field must exist in the search result hits
- Explain that not all search indexes contain image content
- Tell the agent to check for the field before calling the tool

### Decision: Fix tool descriptions + harden validation

- **Decision**: Two-pronged fix: (1) Rewrite tool descriptions to prevent the call, (2) Switch validation from allowlist to denylist for defense in depth
- **Rationale**: The tool description is the primary fix (prevents the bad call entirely). The validation change is secondary (handles future edge cases with extensionless paths and provides better error messages when agents still make mistakes)
- **Alternatives considered**:
  - Only fix validation → wouldn't prevent the AI agent from calling the tool on text-only indexes
  - Only fix tool descriptions → wouldn't protect against extensionless paths in future index schemas
  - Add a `has_images` flag to search results → over-engineering for a single-file MCP server

## Research Task 2: Index Schema Differences and Image Availability

### Findings

| Feature | Multimodal-RAG Index | Bicep-Provisioned Index |
|---------|---------------------|----------------------|
| Has `content_path` | YES — blob-relative path to image | NO |
| Has image content | YES — `normalized_images_N.jpg` | NO — text-only chunks |
| `parent_id` | `text_document_id` | base64-encoded source blob URL |
| `title` | `document_title` | Source filename (e.g., `*.pdf`, `*.docx`) |
| Image retrieval possible | YES | NO |

The `get_image_from_content_path` tool is **only usable with the multimodal-RAG index**. When connected to the Bicep-provisioned index, there are no images to retrieve.

### Decision: Tool description must indicate dependency on `content_path` field

- **Decision**: The tool description should explicitly tell the AI agent: "Only call this tool when a search result hit contains a `content_path` field with a value that looks like a blob image path (not a document URL). If search results do not include a `content_path` field, there are no images to retrieve."
- **Rationale**: This directly prevents the observed failure pattern

## Research Task 3: Validation Approach — Allowlist vs Denylist

### Findings

Current `_is_likely_image_content_path()` at line 275:

```python
def _is_likely_image_content_path(value: Optional[str]) -> bool:
    ...
    suffix = Path(path_value).suffix.lower()
    return suffix in _IMAGE_EXTENSIONS
```

This **correctly rejected** the PDF URL in production. However, it would also reject:
- Extensionless paths (`container/path/normalized_images_1`)
- Paths with query parameters obscuring the extension
- Any new image format not in `_IMAGE_EXTENSIONS`

A denylist approach is more resilient:
- Reject known non-image extensions: `.pdf`, `.docx`, `.doc`, `.xlsx`, `.xls`, `.pptx`, `.ppt`, `.txt`, `.csv`, `.html`, `.htm`
- Accept everything else (images, extensionless, unknown)
- The download will fail gracefully at the blob level if the path is wrong

### Decision: Switch to denylist

- **Decision**: Replace allowlist with denylist using `_NON_IMAGE_EXTENSIONS`
- **Rationale**: More resilient to future index formats while still catching the most common error (passing a document URL)

## Research Task 4: Error Message Improvement

### Findings

Current error message:
> "content_path '{path}' does not look like an image path. Pass the image content_path from semantic_search, not a source document path."

This message told the agent to "pass the image content_path from semantic_search" — but in this case, semantic_search didn't return any `content_path` field. The agent had no correct path to pass.

### Decision: Error message should mention the `content_path` field explicitly

- **Decision**: Error message should say something like: "content_path '{path}' has a document extension (.pdf). This tool requires the content_path field from a semantic_search result that contains image content. If search results do not include a content_path field, there are no images available to retrieve."
- **Rationale**: Helps the agent understand that the tool is not applicable for this index/result set

## Research Task 5: Server-Side Path Normalization

### Problem

Even with better tool descriptions, LLMs can still:
- Prepend the full blob storage URL
- URL-encode or decode the path incorrectly
- Fabricate paths from other fields like `parent_id`

### Findings

Real `content_path` from the multimodal-RAG index:
```
multimodal-rag-images/aHR0cHM6Ly9hdmNvZWRlbW9haXNlYXJjaG1jcHN0Zy5ibG9iLmNvcmUudXNnb3ZjbG91ZGFwaS5uZXQvbXVsdGltb2RhbC1kYXRhL0NBTExfc1VBU0FpcnNwYWNlTWFuYWdlbWVudEFuZENvbnRyb2xfMjAyNTA5MTIucGRm0/normalized_images_13.jpg
```

Structure: `<image-container>/<base64-encoded-source-doc-url>/normalized_images_N.jpg`

Key insight: The image container (`multimodal-rag-images`) is **different** from `STORAGE_ACCOUNT_CONTAINER_NAME` (which is the search data container, e.g., `aisearchdata`). The container for images is **embedded in the content_path** — the server cannot substitute its own container.

The existing split logic in `_download_blob_image` already handles this correctly:
1. Splits on first `/` → `multimodal-rag-images` + `<base64-path>/normalized_images_13.jpg`
2. Validates first segment as a container name → it passes
3. Uses it as container, rest as blob name

So the "always use `STORAGE_ACCOUNT_CONTAINER_NAME`" approach would be **wrong**. Instead:
- Keep the existing container extraction (split on first `/`)
- Add normalization to strip full blob URL prefix if the LLM prepends one
- The LLM's job is just: pass `content_path` verbatim

### Decision: Strip URL prefix only, keep container extraction

- **Decision**: Normalize input by stripping full blob URL prefix (`https://<account>.blob.core.*/<path>`) to get the relative path, then use existing split-on-first-`/` logic for container extraction
- **Rationale**: The image container differs from the data container; we must respect the container encoded in `content_path`
- **Alternatives considered**:
  - Always use `STORAGE_ACCOUNT_CONTAINER_NAME` → **wrong**, image container is different
  - Accept only exact relative paths → too strict, LLM may prepend URL

## Summary of Decisions

| # | Decision | Type | Rationale |
|---|----------|------|-----------|
| 1 | Rewrite `get_image_from_content_path` tool description | Prompt fix (primary) | Prevents AI agent from calling tool when no `content_path` field exists in results |
| 2 | Switch validation from allowlist to denylist | Code fix (secondary) | Handles extensionless paths, more resilient to future formats |
| 3 | Improve error message | Code fix | Guides agent self-correction when tool is called incorrectly |
| 4 | Add `_NON_IMAGE_EXTENSIONS` constant | Code fix | Defines the denylist for common document extensions |
| 5 | Keep `_IMAGE_EXTENSIONS` for format detection | No change | Still used in `_download_blob_image` for image format detection |
| 6 | Strip URL prefix in normalization, keep container extraction | Code fix (defense in depth) | Image container (`multimodal-rag-images`) differs from `STORAGE_ACCOUNT_CONTAINER_NAME`; container must come from `content_path` |
