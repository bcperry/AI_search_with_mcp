# HTTP Auth Contract: MCP Streamable HTTP Transport

**Date**: 2026-04-22

## Overview

This contract defines the authentication behavior on the MCP server's streamable HTTP transport endpoint. Auth is purely at the HTTP layer — the MCP protocol and tool interfaces are unchanged.

## Endpoint

All MCP HTTP transport requests (typically `POST /mcp` or configured endpoint).

## Authentication Header

```
Authorization: Bearer <jwt-token>
```

## Behavior Matrix

| `AZURE_AD_REQUIRE_AUTH` | Token Present & Valid | Token Present & Invalid | Token Missing |
|------------------------|-----------------------|------------------------|---------------|
| `true` | **200** — proceed normally | **401** — reject | **401** — reject |
| `false` (default) | Proceed (fallback to MCP_AUTH_SECRET if set) | Fallback auth behavior | Fallback auth behavior |

## Error Response (HTTP 401)

When Azure AD auth is enabled and the token is invalid/missing:

```http
HTTP/1.1 401 Unauthorized
Content-Type: application/json

{"error": "unauthorized", "detail": "<reason>"}
```

**Security**: The response MUST NOT echo the token value. The `detail` field describes the failure reason (e.g., "expired token", "invalid signature", "missing authorization header").

Note: The exact 401 response format is determined by FastMCP's Starlette `AuthenticationMiddleware`. The server does not customize this response body.

## Token Requirements

| Field | Requirement |
|-------|-------------|
| Algorithm | RS256 |
| Issuer (`iss`) | `https://login.microsoftonline.us/<tenant>/v2.0` (Gov) or `https://login.microsoftonline.com/<tenant>/v2.0` (Commercial) |
| Audience (`aud`) | `api://<AZURE_AD_CLIENT_ID>` |
| Expiration (`exp`) | Must be in the future |
| Signature | Valid against Azure AD JWKS endpoint |

## Configuration Contract

| Environment Variable | Required | Description |
|---------------------|----------|-------------|
| `AZURE_AD_REQUIRE_AUTH` | No (default `false`) | Enable Azure AD auth |
| `AZURE_AD_TENANT_ID` | When auth enabled | Azure AD tenant ID |
| `AZURE_AD_CLIENT_ID` | When auth enabled | MCP server app registration client ID |
| `CLOUD_NAME` | No | `AzureUSGovernment` for Gov cloud |

## Startup Validation

When `AZURE_AD_REQUIRE_AUTH=true`:
- If `AZURE_AD_TENANT_ID` is not set → `RuntimeError` at startup
- If `AZURE_AD_CLIENT_ID` is not set → `RuntimeError` at startup
- Log at INFO: auth mode, issuer URL, audience (never log secrets/tokens)

## Backward Compatibility

- Default behavior (`AZURE_AD_REQUIRE_AUTH=false`) is identical to current behavior
- Existing `MCP_AUTH_SECRET` HS256 auth continues to work as fallback
- No changes to MCP tool signatures or response formats
