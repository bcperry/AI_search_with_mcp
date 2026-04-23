# Quickstart: Fix Search Select Fields Mismatch

**Date**: 2026-04-23

## What Changed

The `semantic_search` MCP tool now dynamically discovers index field names, vector field, and semantic configuration from the Azure AI Search index schema at server startup instead of relying on hardcoded field lists.

## Verification

### 1. Start the server

```bash
python main.py
```

### 2. Check startup logs

You should see INFO-level log messages like:

```
Introspected index 'your-index-name': select_fields=['chunk_id', 'parent_id', 'chunk', 'title', 'content_path'], vector_field='text_vector', semantic_config='index-and-vectorize-semantic-configuration'
```

### 3. Test semantic_search tool

Call the `semantic_search` tool with any query. It should return results without the `content_id` property error.

### 4. Verify with different index schemas

The server works with both:
- **Bicep-provisioned index** (`chunk_id`, `parent_id`, `chunk`, `title`, `text_vector`)
- **Multimodal-RAG index** (`content_id`, `text_document_id`, `document_title`, `content_text`, `content_embedding`, `content_path`, etc.)

### Environment Variable Overrides

If you need to override discovered fields:

```env
SEARCH_SELECT_FIELDS=content_id,document_title,content_text,content_path
SEARCH_VECTOR_FIELD_NAME=content_embedding
SEARCH_SEMANTIC_CONFIGURATION_NAME=multimodal-rag-semantic-configuration
```
