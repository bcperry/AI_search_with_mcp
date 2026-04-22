<!--
  Sync Impact Report
  ==================
  Version change: N/A → 1.0.0 (initial ratification)
  Modified principles: none (initial)
  Added sections:
    - Core Principles (5 principles)
    - Technology Stack Constraints
    - Security Requirements
    - Governance
  Removed sections: none
  Templates requiring updates:
    - .specify/templates/plan-template.md ✅ compatible (Constitution Check section is generic)
    - .specify/templates/spec-template.md ✅ compatible (no principle-specific references)
    - .specify/templates/tasks-template.md ✅ compatible (no principle-specific references)
  Follow-up TODOs: none
-->

# AI Search with MCP Constitution

## Core Principles

### I. Infrastructure as Code

All Azure resources MUST be defined in Bicep templates under the
`infra/` directory. Manual portal changes are prohibited. Every
resource, role assignment, and configuration MUST be reproducible
via `azd up`. Changes to infrastructure MUST be reviewed in pull
requests the same as application code.

**Rationale**: Reproducibility eliminates environment drift and
enables reliable multi-environment deployments.

### II. Security by Default

- Authentication MUST use Microsoft Entra ID (Azure AD) with
  managed identities. Storing secrets, connection strings, or
  API keys in code or configuration files is prohibited.
- The `ChainedTokenCredential` pattern MUST be used for local
  development (CLI credential) and deployed environments
  (managed identity) without code changes.
- MCP server endpoints MUST support JWT-based authentication
  via `MCP_AUTH_SECRET` when deployed; unauthenticated mode is
  permitted only in local development.
- All role assignments MUST follow least-privilege: grant only
  the minimum Azure RBAC roles required for each identity.

**Rationale**: Zero-secret architectures eliminate an entire
class of credential-leak vulnerabilities.

### III. Cloud Portability

The codebase MUST support both Azure Commercial and Azure
Government (GCC-High) clouds without forking. Cloud-specific
behavior (authority hosts, audiences, endpoints) MUST be driven
by the `CLOUD_NAME` environment variable. No cloud-specific
URLs or constants may be hard-coded outside of a centralized
configuration function.

**Rationale**: Government customers require GCC-High support;
a single codebase reduces maintenance burden and divergence
risk.

### IV. MCP Protocol Compliance

Every tool exposed by the server MUST conform to the Model
Context Protocol specification via the `FastMCP` framework.
Tools MUST:
- Accept clearly typed parameters with descriptions.
- Return structured JSON-serializable responses.
- Handle errors gracefully and return meaningful error messages
  rather than raw exceptions.
- Exclude vector/embedding payloads from returned results to
  keep responses within MCP size constraints.

**Rationale**: Strict MCP compliance ensures interoperability
with any MCP-compatible client or agent framework.

### V. Observability

- All modules MUST use Python `logging` with structured messages
  (include operation name, resource identifiers, and timing where
  relevant).
- Azure SDK diagnostic strings MUST be captured when latency
  exceeds expected thresholds or when unexpected status codes
  are returned.
- Deployed environments MUST integrate with Azure Monitor /
  Application Insights for end-to-end tracing.
- Log levels MUST follow: DEBUG for internal flow, INFO for
  operations, WARNING for recoverable issues, ERROR for failures.

**Rationale**: Structured observability is non-negotiable for
diagnosing issues in distributed Azure services.

## Technology Stack Constraints

| Layer | Technology | Version Constraint |
|-------|------------|--------------------|
| Language | Python | >= 3.10 |
| MCP Framework | FastMCP | >= 2.x |
| Azure Identity | azure-identity | >= 1.x |
| Search SDK | azure-search-documents | >= 11.x |
| Blob SDK | azure-storage-blob | >= 12.x |
| Infrastructure | Bicep | latest via `azd` |
| Deployment | Azure Developer CLI (`azd`) | latest stable |
| Hosting | Azure App Service (Linux) | Python 3.10+ |
| Package Management | `uv` / `pip` with `pyproject.toml` | — |

- New dependencies MUST be added to both `pyproject.toml` and
  `requirements.txt`.
- Azure SDK packages MUST be pinned to major version ranges to
  avoid breaking changes.
- Bicep modules MUST NOT use preview API versions in production
  deployments unless no stable alternative exists (document the
  exception in the module header).

## Security Requirements

- **Network**: Deployed services SHOULD use private endpoints
  or VNet integration where feasible. Public endpoints MUST
  require authentication.
- **Data in transit**: All service-to-service communication
  MUST use TLS 1.2+.
- **RBAC**: Role assignments MUST be defined in Bicep (see
  `*RoleAssignment.bicep` modules). Manual Azure Portal role
  grants are prohibited.
- **Input validation**: All MCP tool inputs MUST be validated
  at the boundary before being passed to Azure SDK calls.
  Container names, index names, and blob paths MUST be
  validated against expected patterns.
- **Secrets rotation**: The `MCP_AUTH_SECRET` used for JWT
  signing MUST be stored in Azure App Service configuration
  (not in source control) and rotated on a regular cadence.

## Governance

This constitution is the authoritative governance document for
the AI Search with MCP project. It supersedes ad-hoc practices
and informal conventions.

- **Amendments**: Any change to this constitution MUST be
  submitted as a pull request with a clear rationale. The
  version MUST be incremented per semantic versioning:
  MAJOR for principle removals/redefinitions, MINOR for
  additions, PATCH for clarifications.
- **Compliance**: All pull requests MUST be reviewed against
  the applicable principles before merge. The plan template's
  "Constitution Check" gate references these principles.
- **Simplicity**: Favor the simplest solution that satisfies
  requirements (YAGNI). Complexity MUST be justified in the
  plan's Complexity Tracking table before implementation.
- **Conflict resolution**: When principles conflict, Security
  by Default takes precedence, followed by Cloud Portability,
  then the remaining principles in order.

**Version**: 1.0.0 | **Ratified**: 2026-04-22 | **Last Amended**: 2026-04-22
