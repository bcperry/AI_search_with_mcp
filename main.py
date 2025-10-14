from typing import Any
from fastmcp import FastMCP

mcp = FastMCP("Azure AI Search MCP")


@mcp.tool()
async def ai_search(query: str) -> dict[str, Any]:
    """Placeholder"""

    return {"result": "Not yet implemented"}


if __name__ == "__main__":
    mcp.run(transport="streamable-http", host="0.0.0.0", port=8000)
