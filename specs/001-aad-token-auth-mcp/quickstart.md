# Quickstart: Azure AD Token Authentication for MCP Server

## Prerequisites

1. Azure AD app registration for this MCP server
2. `AZURE_AD_TENANT_ID` and `AZURE_AD_CLIENT_ID` values from the app registration
3. A calling application configured with permission to call this API

## Enable Azure AD Auth

Add to your `.env` or Azure App Service configuration:

```env
AZURE_AD_REQUIRE_AUTH=true
AZURE_AD_TENANT_ID=<your-tenant-id>
AZURE_AD_CLIENT_ID=<your-mcp-app-client-id>
CLOUD_NAME=AzureUSGovernment   # omit for commercial cloud
```

## Azure AD App Registration Setup

1. **Register the MCP server app** in Azure AD:
   - Go to Azure Portal → Azure Active Directory → App registrations → New registration
   - Name: `mcp-azure-ai-search` (or your preferred name)
   - Supported account types: Single tenant
   - No redirect URI needed (server-only)

2. **Expose an API**:
   - App registrations → your app → Expose an API
   - Set Application ID URI: `api://<client-id>`
   - Add a scope: `api://<client-id>/.default`

3. **Grant calling application permission**:
   - The backend/web-agents app registration needs "API permissions" → Add a permission → My APIs → select your MCP server app → select the `.default` scope
   - Grant admin consent

4. **Configure environment**:
   - Set `AZURE_AD_TENANT_ID` = your tenant ID
   - Set `AZURE_AD_CLIENT_ID` = the MCP server app's client ID (Application ID)

## Verify Auth is Working

```bash
# Start the server
python main.py

# Expect log output:
# INFO: Azure AD auth enabled – issuer=https://login.microsoftonline.us/<tenant>/v2.0, audience=api://<client-id>
```

```bash
# Request without token → 401
curl -X POST http://localhost:8000/mcp -H "Content-Type: application/json" -d '{}'
# HTTP 401

# Request with valid Azure AD token → 200
curl -X POST http://localhost:8000/mcp \
  -H "Authorization: Bearer <valid-token>" \
  -H "Content-Type: application/json" \
  -d '{"method": "tools/list", "params": {}}'
# HTTP 200
```

## Disable Auth (Development)

```env
AZURE_AD_REQUIRE_AUTH=false
# or simply omit the variable
```

With auth disabled, existing behavior is preserved (falls back to `MCP_AUTH_SECRET` if set, otherwise no auth).
