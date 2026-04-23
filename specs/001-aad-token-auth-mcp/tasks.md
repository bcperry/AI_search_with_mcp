# Tasks: Azure AD Token Authentication for MCP HTTP Requests

**Input**: Design documents from `/specs/001-aad-token-auth-mcp/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/http-auth.md, quickstart.md

**Tests**: Not explicitly requested in spec — test tasks omitted.

**Organization**: Tasks grouped by user story. This is a small feature (~30 lines of config change in `main.py` + README docs) using FastMCP's built-in `JWTVerifier` with `jwks_uri`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Exact file paths included in descriptions

---

## Phase 1: Setup

**Purpose**: No new project structure needed — this feature modifies existing files only.

- [x] T001 Verify FastMCP `JWTVerifier` supports `jwks_uri` parameter by checking installed fastmcp version in pyproject.toml

**Checkpoint**: Confirmed FastMCP >= 2.12.4 with JWKS support is available.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Extract cloud-aware Azure AD endpoint helper used by the auth builder.

**⚠️ CRITICAL**: The endpoint helper must be in place before the auth builder can reference it.

- [x] T002 Implement `_get_azure_ad_login_host()` helper function in main.py that returns `login.microsoftonline.us` when `CLOUD_NAME=AzureUSGovernment` and `login.microsoftonline.com` otherwise (follows existing `_apply_cloud_authority_from_env()` pattern)

**Checkpoint**: Cloud-aware login host derivation ready.

---

## Phase 3: User Story 1 — Azure AD Auth Toggle & JWT Validation (Priority: P1) 🎯 MVP

**Goal**: When `AZURE_AD_REQUIRE_AUTH=true`, the MCP server validates incoming `Authorization: Bearer <token>` headers as Azure AD RS256 JWTs against the JWKS endpoint. When `false` (default), existing behavior is preserved.

**Independent Test**: Start server with `AZURE_AD_REQUIRE_AUTH=true`, `AZURE_AD_TENANT_ID`, `AZURE_AD_CLIENT_ID` set → server logs Azure AD auth mode. Send request without token → HTTP 401. With `AZURE_AD_REQUIRE_AUTH=false` → server accepts all requests as before.

### Implementation for User Story 1

- [x] T003 [US1] Extend `_build_auth()` in main.py to check `AZURE_AD_REQUIRE_AUTH` env var first: when `true`, read `AZURE_AD_TENANT_ID` and `AZURE_AD_CLIENT_ID` from environment, raise `RuntimeError` if either is missing, derive issuer and JWKS URI using `_get_azure_ad_login_host()`, and return `JWTVerifier(jwks_uri=..., issuer=..., audience=f"api://{client_id}", algorithm="RS256")`
- [x] T004 [US1] Preserve existing `MCP_AUTH_SECRET` fallback path in `_build_auth()` in main.py: when `AZURE_AD_REQUIRE_AUTH` is not `true`, fall through to existing HS256 `JWTVerifier` logic (current behavior unchanged)
- [x] T005 [US1] Add INFO-level startup log messages in `_build_auth()` in main.py indicating which auth mode is active: Azure AD (with issuer and audience, never tokens), MCP_AUTH_SECRET, or no auth

**Checkpoint**: Azure AD auth toggle functional. Server validates Azure AD JWTs when enabled, falls back to existing behavior when disabled.

---

## Phase 4: User Story 2 — README Documentation (Priority: P2)

**Goal**: Document Azure AD app registration setup, environment variables, and configuration in README so operators can enable auth.

**Independent Test**: Read README → follow instructions to configure Azure AD auth → verify server starts with auth enabled.

### Implementation for User Story 2

- [x] T006 [P] [US2] Add "Authentication" section to README.md documenting: Azure AD app registration steps (register app, expose API scope `api://<client-id>/.default`, grant calling app permission), environment variables (`AZURE_AD_REQUIRE_AUTH`, `AZURE_AD_TENANT_ID`, `AZURE_AD_CLIENT_ID`, `CLOUD_NAME`), auth priority logic (Azure AD → MCP_AUTH_SECRET → no auth), and how to verify auth is working
- [x] T007 [P] [US2] Add `AZURE_AD_REQUIRE_AUTH`, `AZURE_AD_TENANT_ID`, `AZURE_AD_CLIENT_ID` placeholder entries to .env.example or document in README.md environment variables table

**Checkpoint**: README contains complete app registration and configuration guide.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and cleanup.

- [x] T008 [P] Run quickstart.md validation: start server with `AZURE_AD_REQUIRE_AUTH=true` and verify startup log output matches expected format
- [x] T009 [P] Verify backward compatibility: start server without any `AZURE_AD_*` env vars set and confirm existing behavior (MCP_AUTH_SECRET fallback or no auth) is unchanged
- [x] T010 Review main.py `_build_auth()` to confirm no token values are logged — only auth mode, issuer URL, and audience

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 confirmation
- **User Story 1 (Phase 3)**: Depends on Phase 2 (`_get_azure_ad_login_host()` helper)
- **User Story 2 (Phase 4)**: Can start after Phase 1 — documentation is independent of code
- **Polish (Phase 5)**: Depends on Phase 3 completion (needs working auth to validate)

### User Story Dependencies

- **User Story 1 (P1)**: Depends on Foundational phase only — core implementation
- **User Story 2 (P2)**: Independent of US1 — documentation can be written in parallel

### Within User Story 1

- T003 before T004 (Azure AD path before fallback path — same function, sequential edits)
- T004 before T005 (complete auth logic before adding logging)

### Parallel Opportunities

- T006 and T007 (both documentation, different sections)
- T008, T009, T010 (independent validation checks)
- US2 (documentation) can be worked in parallel with US1 (code)

---

## Parallel Example: User Story 1

```bash
# Sequential within US1 (same function in same file):
Task T003: Extend _build_auth() with Azure AD JWKS path
Task T004: Preserve MCP_AUTH_SECRET fallback
Task T005: Add startup logging
```

## Parallel Example: Across User Stories

```bash
# Can run in parallel (different files):
US1 Task T003-T005: Code changes in main.py
US2 Task T006-T007: Documentation in README.md
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Verify FastMCP version
2. Complete Phase 2: Add `_get_azure_ad_login_host()` helper
3. Complete Phase 3: Extend `_build_auth()` with Azure AD support
4. **STOP and VALIDATE**: Test with `AZURE_AD_REQUIRE_AUTH=true` and real Azure AD tokens
5. Deploy if ready

### Incremental Delivery

1. Setup + Foundational → Helper function ready
2. User Story 1 → Auth toggle working → Deploy (MVP!)
3. User Story 2 → Documentation complete → Share with operators
4. Polish → All validations pass

---

## Notes

- Total tasks: 10
- User Story 1 (code): 3 tasks (T003–T005) — all in main.py
- User Story 2 (docs): 2 tasks (T006–T007) — README.md
- No new dependencies (FastMCP's JWTVerifier handles everything)
- No new files created (auth.py not needed)
- Suggested MVP scope: User Story 1 only (Phase 1–3)
