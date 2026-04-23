# Feature Specification: Azure AD Token Authentication for MCP HTTP Requests

**Branch**: `001-aad-token-auth-mcp` | **Date**: 2026-04-22

## Overview

Implement Azure AD (Microsoft Entra ID) bearer token validation on all incoming MCP HTTP requests (streamable HTTP transport). The MCP server receives authenticated requests from a backend that forwards user Azure AD bearer tokens via `Authorization: Bearer <token>` headers. The server validates these tokens against its own Azure AD app registration.

## Requirements

### Functional Requirements

1. **Token Extraction**: Extract `Authorization: Bearer <token>` header from all incoming MCP HTTP requests on the streamable HTTP transport endpoint.

2. **JWT Validation**: Validate the bearer token as an Azure AD JWT:
   - **Issuer**: `https://login.microsoftonline.us/<tenant-id>/v2.0` (Azure Government)
   - **Audience**: The MCP server's own Azure AD app registration client ID (`api://<mcp-client-id>`)
   - **Signature**: Validate against Azure AD JWKS endpoint (`https://login.microsoftonline.us/<tenant-id>/discovery/v2.0/keys`)
   - **Expiration**: Reject expired tokens

3. **JWKS Key Caching**: Cache JWKS keys to avoid fetching on every request.

4. **Configuration via Environment Variables**:
   - `AZURE_AD_TENANT_ID` — Azure AD tenant ID
   - `AZURE_AD_CLIENT_ID` — MCP server's app registration client ID (expected audience)
   - `AZURE_AD_REQUIRE_AUTH` — `true`/`false` toggle (default `false`)

5. **Auth Toggle Behavior**:
   - `AZURE_AD_REQUIRE_AUTH=true`: Reject requests without a valid token with HTTP 401
   - `AZURE_AD_REQUIRE_AUTH=false`: Accept all requests (current behavior, no change)

6. **Error Responses**: On invalid/expired token, return HTTP 401 with `{"error": "unauthorized", "detail": "..."}`. Never echo the token in error responses.

7. **User Identity in Context**: On valid token, optionally make authenticated user claims (`oid`, `preferred_username`, `name`) available to tool handlers via request context for audit logging.

### Non-Functional Requirements

1. **Backward Compatibility**: Default `AZURE_AD_REQUIRE_AUTH=false` preserves existing unauthenticated behavior.
2. **Security**: Never log token values. Log auth success/failure events with user identity only.
3. **Cloud Portability**: Support Azure Government (`login.microsoftonline.us`) issuer and JWKS endpoints, driven by existing `CLOUD_NAME` environment variable pattern.
4. **Performance**: JWKS key caching to avoid per-request key fetches.

### Out of Scope

- OAuth login flows — server only validates incoming tokens
- Changes to MCP protocol/tool interface — auth is purely HTTP transport layer
- Token acquisition — the calling backend handles this

## App Registration Setup (to document in README)

1. Register the MCP server as an app in Azure AD
2. Expose an API scope (e.g., `api://<client-id>/.default`)
3. Grant the calling application permission to call this API (enables On-Behalf-Of flow)
4. Add `AZURE_AD_TENANT_ID` and `AZURE_AD_CLIENT_ID` to deployment environment

## Dependencies

- `PyJWT` + `cryptography` for JWT validation
- `aiohttp` (already present) for JWKS key fetching
