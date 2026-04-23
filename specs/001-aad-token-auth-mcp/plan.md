# Implementation Plan: Azure AD Token Authentication for MCP HTTP Requests

**Branch**: `001-aad-token-auth-mcp` | **Date**: 2026-04-22 | **Spec**: [spec.md](specs/001-aad-token-auth-mcp/spec.md)
**Input**: Feature specification from `/specs/001-aad-token-auth-mcp/spec.md`

## Summary

Add Azure AD (Microsoft Entra ID) bearer token validation to the MCP server's streamable HTTP transport endpoint. When enabled via `AZURE_AD_REQUIRE_AUTH=true`, all incoming requests must carry a valid `Authorization: Bearer <token>` header. Tokens are validated as Azure AD JWTs against the server's app registration (issuer, audience, signature via JWKS, expiration). Uses PyJWT + cryptography with cached JWKS keys. Defaults to off (`false`) for backward compatibility.

## Technical Context

**Language/Version**: Python >= 3.10 (per pyproject.toml)  
**Primary Dependencies**: FastMCP >= 2.x (built-in JWTVerifier with JWKS support), azure-identity, aiohttp (existing)  
**Storage**: N/A (stateless auth middleware)  
**Testing**: pytest (to be added for auth validation)  
**Target Platform**: Azure App Service (Linux), local development  
**Project Type**: Web service (MCP server via streamable HTTP)  
**Performance Goals**: JWKS key caching to avoid per-request HTTP fetches; sub-millisecond token validation after key cache warm  
**Constraints**: Must support Azure Government (login.microsoftonline.us) via CLOUD_NAME; must not break existing unauthenticated deployments  
**Scale/Scope**: Single MCP server process; auth is per-request middleware

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Infrastructure as Code | PASS | No new Azure resources required for auth middleware itself. App registration is an Azure AD config concern, not a Bicep resource. Environment variables are set via App Service config (already IaC). |
| II. Security by Default | PASS | Uses Microsoft Entra ID (Azure AD) JWT validation. No secrets stored in code — `AZURE_AD_CLIENT_ID` and `AZURE_AD_TENANT_ID` are non-secret identifiers. JWKS keys fetched from Azure AD. Existing `MCP_AUTH_SECRET` path preserved as fallback. |
| III. Cloud Portability | PASS | Azure Government issuer (`login.microsoftonline.us`) and JWKS endpoints driven by `CLOUD_NAME` env var, consistent with existing pattern. Commercial cloud (`login.microsoftonline.com`) also supported. |
| IV. MCP Protocol Compliance | PASS | Auth is at the HTTP transport layer only. No changes to MCP tool interfaces or protocol. |
| V. Observability | PASS | Auth success/failure logged via Python logging. Token values never logged — only user identity (oid, preferred_username). |

**Gate Result**: PASS — no violations.

### Post-Phase 1 Re-Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Infrastructure as Code | PASS | No new Azure resources. No new Bicep modules. |
| II. Security by Default | PASS | Uses FastMCP's built-in `JWTVerifier` with JWKS+RS256. No new secrets introduced. No token logging. |
| III. Cloud Portability | PASS | Issuer/JWKS URIs derived from `CLOUD_NAME` + `AZURE_AD_TENANT_ID`. Both Gov and Commercial supported. |
| IV. MCP Protocol Compliance | PASS | No changes to tools, parameters, or response formats. |
| V. Observability | PASS | Startup logs indicate auth mode. Token values never logged. |
| Tech Stack Constraints | PASS | No new dependencies — FastMCP's JWTVerifier uses authlib (transitive dep). No changes to `requirements.txt` or `pyproject.toml`. |
| Simplicity (Governance) | PASS | Reuses built-in FastMCP auth. ~30 lines of config change in `main.py`. No custom auth module. |

**Post-Design Gate Result**: PASS — no violations.

## Project Structure

### Documentation (this feature)

```text
specs/001-aad-token-auth-mcp/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
main.py                  # Modified — extend _build_auth() for Azure AD JWKS-based JWTVerifier
tests/
└── test_auth.py         # New — unit tests for auth configuration logic
README.md                # Updated — document app registration setup
```

**Structure Decision**: No new modules. FastMCP's built-in `JWTVerifier` with `jwks_uri` + `RS256` handles Azure AD JWT validation natively — no custom `auth.py` or new dependencies needed. The existing `_build_auth()` function in `main.py` is extended to conditionally configure Azure AD auth. No changes to `requirements.txt` or `pyproject.toml`.

## Complexity Tracking

> No Constitution Check violations — table not required.
