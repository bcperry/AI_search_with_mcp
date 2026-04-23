# Data Model: Azure AD Token Authentication

**Date**: 2026-04-22

## Overview

This feature is stateless HTTP middleware — no persistent data entities are introduced. This document describes the runtime data structures involved in auth configuration and token validation.

## Configuration Model

### Environment Variables

| Variable | Type | Required When | Default | Description |
|----------|------|---------------|---------|-------------|
| `AZURE_AD_REQUIRE_AUTH` | `str` (bool-like) | Always | `"false"` | Enable Azure AD token validation |
| `AZURE_AD_TENANT_ID` | `str` (UUID) | `AZURE_AD_REQUIRE_AUTH=true` | — | Azure AD tenant ID |
| `AZURE_AD_CLIENT_ID` | `str` (UUID) | `AZURE_AD_REQUIRE_AUTH=true` | — | MCP server app registration client ID |
| `CLOUD_NAME` | `str` | Never (existing) | `""` | Cloud selector: `"AzureUSGovernment"` or empty for commercial |
| `MCP_AUTH_SECRET` | `str` | Fallback auth | — | Existing HS256 symmetric key (preserved) |
| `MCP_AUTH_ISSUER` | `str` | Fallback auth | `"mcp-issuer"` | Existing JWT issuer (preserved) |
| `MCP_AUTH_AUDIENCE` | `str` | Fallback auth | `"azure-ai-search-mcp"` | Existing JWT audience (preserved) |

### Auth Priority

```
AZURE_AD_REQUIRE_AUTH=true?
  ├── YES → JWTVerifier(jwks_uri=..., issuer=..., audience=..., algorithm="RS256")
  │         Requires: AZURE_AD_TENANT_ID, AZURE_AD_CLIENT_ID
  │         Raises RuntimeError if either is missing
  └── NO
        MCP_AUTH_SECRET set?
        ├── YES → JWTVerifier(public_key=..., algorithm="HS256", issuer=..., audience=...)
        │         (current behavior, unchanged)
        └── NO → None (no auth, current default)
```

## Derived Endpoints

| Field | Azure Government (`AzureUSGovernment`) | Azure Commercial (default) |
|-------|---------------------------------------|---------------------------|
| Login host | `login.microsoftonline.us` | `login.microsoftonline.com` |
| Issuer | `https://{host}/{tenant_id}/v2.0` | `https://{host}/{tenant_id}/v2.0` |
| JWKS URI | `https://{host}/{tenant_id}/discovery/v2.0/keys` | `https://{host}/{tenant_id}/discovery/v2.0/keys` |
| Audience | `api://{client_id}` | `api://{client_id}` |

## Runtime Token Structure (Azure AD v2.0 JWT Claims)

These claims are available in `AccessToken.claims` after successful validation:

| Claim | Type | Description | Used For |
|-------|------|-------------|----------|
| `iss` | `str` | Issuer URL | Validated by JWTVerifier |
| `aud` | `str` | Audience (app client ID) | Validated by JWTVerifier |
| `exp` | `int` | Expiration timestamp | Validated by JWTVerifier |
| `iat` | `int` | Issued-at timestamp | Informational |
| `nbf` | `int` | Not-before timestamp | Validated by authlib |
| `sub` | `str` | Subject (user/app ID) | Audit logging |
| `oid` | `str` | Object ID (user GUID) | Audit logging |
| `preferred_username` | `str` | User's email/UPN | Audit logging |
| `name` | `str` | Display name | Audit logging |
| `scp` | `str` | Space-delimited scopes | Extracted by JWTVerifier |
| `tid` | `str` | Tenant ID | Informational |
| `azp` | `str` | Authorized party (calling app) | Informational |

## State Transitions

N/A — stateless middleware. Each request is validated independently.

## Validation Rules

| Rule | Enforcement |
|------|-------------|
| `AZURE_AD_TENANT_ID` must be set when `AZURE_AD_REQUIRE_AUTH=true` | `RuntimeError` at startup |
| `AZURE_AD_CLIENT_ID` must be set when `AZURE_AD_REQUIRE_AUTH=true` | `RuntimeError` at startup |
| Token must have valid RS256 signature | JWTVerifier via JWKS |
| Token must not be expired | JWTVerifier (exp claim) |
| Token issuer must match configured issuer | JWTVerifier |
| Token audience must match configured audience | JWTVerifier |
| Token values must never be logged | Code review / security policy |
