# Research: Azure AD Token Authentication for MCP HTTP Requests

**Date**: 2026-04-22

## R1: FastMCP Built-in Auth for Azure AD JWT Validation

### Decision: Use FastMCP's built-in `JWTVerifier` with `jwks_uri`

### Rationale

FastMCP >= 2.12.4 ships with a `JWTVerifier` class (`fastmcp.server.auth.providers.jwt`) that natively supports:

- **`jwks_uri` parameter**: Fetches RSA public keys from Azure AD's JWKS endpoint
- **RS256 algorithm** (default): Matches Azure AD's JWT signing algorithm
- **Issuer validation**: Verifiable against `https://login.microsoftonline.us/<tenant>/v2.0` (Gov) or `https://login.microsoftonline.com/<tenant>/v2.0` (Commercial)
- **Audience validation**: Supports single string or list of audiences
- **JWKS key caching**: 1-hour TTL, keyed by `kid` header — avoids per-request fetches
- **Scope extraction**: Supports both `scope` and `scp` claims (Azure AD uses `scp`)
- **Full claims in AccessToken**: `AccessToken.claims` dict contains all JWT claims including `oid`, `preferred_username`, `name`

This eliminates the need for a custom `auth.py` module. The existing `_build_auth()` function in `main.py` just needs to be extended to conditionally return an Azure AD-configured `JWTVerifier` when `AZURE_AD_REQUIRE_AUTH=true`.

### Alternatives Considered

| Alternative | Rejected Because |
|-------------|-----------------|
| Custom `TokenVerifier` subclass with PyJWT | Unnecessary — `JWTVerifier` already handles JWKS+RS256 natively via authlib |
| `AzureTokenVerifier` (built-in) | Validates tokens via Microsoft Graph API call per request — too slow, requires network round-trip |
| `AzureProvider` (built-in) | Full OAuth proxy — implements login flows, which the spec explicitly excludes |
| PyJWT + cryptography | Would add redundant dependencies; FastMCP uses authlib internally |

### Dependencies Impact

- **No new dependencies required** — FastMCP's `JWTVerifier` uses `authlib` (already a FastMCP transitive dependency) for JWKS fetching and JWT decoding
- `PyJWT` and `cryptography` are NOT needed — removes two dependencies from the original spec

## R2: Azure AD Endpoints by Cloud

### Decision: Derive issuer and JWKS URI from `CLOUD_NAME` and `AZURE_AD_TENANT_ID`

### Rationale

Consistent with Constitution Principle III (Cloud Portability), endpoints are driven by `CLOUD_NAME`:

| Cloud | `CLOUD_NAME` | Issuer | JWKS URI |
|-------|-------------|--------|----------|
| Azure Government | `AzureUSGovernment` | `https://login.microsoftonline.us/{tenant}/v2.0` | `https://login.microsoftonline.us/{tenant}/discovery/v2.0/keys` |
| Azure Commercial | (default/empty) | `https://login.microsoftonline.com/{tenant}/v2.0` | `https://login.microsoftonline.com/{tenant}/discovery/v2.0/keys` |

This follows the existing `_apply_cloud_authority_from_env()` pattern in `main.py`.

### Alternatives Considered

| Alternative | Rejected Because |
|-------------|-----------------|
| Hardcode Azure Government endpoints only | Violates Cloud Portability principle |
| Separate env vars for issuer/JWKS URL | Unnecessary complexity — derivable from CLOUD_NAME + tenant |

## R3: Auth Toggle Design

### Decision: `AZURE_AD_REQUIRE_AUTH` env var controls auth behavior

### Rationale

- `AZURE_AD_REQUIRE_AUTH=true` → return `JWTVerifier` configured for Azure AD (JWKS + RS256)
- `AZURE_AD_REQUIRE_AUTH=false` (default) → fall back to existing `MCP_AUTH_SECRET` behavior if set, otherwise no auth
- This preserves backward compatibility with existing deployments using `MCP_AUTH_SECRET`

### Auth Priority Logic

1. If `AZURE_AD_REQUIRE_AUTH=true`: use Azure AD JWKS-based `JWTVerifier` (requires `AZURE_AD_TENANT_ID` and `AZURE_AD_CLIENT_ID`)
2. Else if `MCP_AUTH_SECRET` is set: use existing HS256 `JWTVerifier` (current behavior)
3. Else: no auth (current default behavior)

## R4: User Identity in Request Context

### Decision: Claims are available automatically via FastMCP's `AccessToken.claims`

### Rationale

When `JWTVerifier` validates a token, it returns an `AccessToken` with a `claims` dict containing all JWT claims. FastMCP's middleware stores this on the Starlette request state. Tool handlers can access the authenticated user's identity (`oid`, `preferred_username`, `name`) from the request context without additional plumbing.

No custom middleware or context injection needed — this is built into FastMCP.

## R5: Error Response Format

### Decision: FastMCP handles 401 responses automatically

### Rationale

When `JWTVerifier.verify_token()` returns `None` (invalid token), FastMCP's Starlette `AuthenticationMiddleware` automatically returns HTTP 401. The error response body format is handled by FastMCP's middleware.

Custom error formatting (e.g., `{"error": "unauthorized", "detail": "..."}`) would require subclassing, but FastMCP's default 401 behavior is sufficient and consistent with the framework.

## R6: Logging Considerations

### Decision: Log auth events at appropriate levels, never log tokens

### Rationale

- **Auth enabled**: Log at INFO level when Azure AD auth is configured (issuer, audience — not secrets)
- **Auth success**: Existing FastMCP middleware handles this
- **Auth failure**: FastMCP returns 401; failures are visible in HTTP access logs
- **Token values**: Never logged — Constitution Principle II (Security by Default)
- Add startup log message indicating which auth mode is active
