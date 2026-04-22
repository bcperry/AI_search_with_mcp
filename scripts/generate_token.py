import argparse
import base64
import hashlib
import hmac
import json
import os
import sys
import time
from pathlib import Path
from typing import Any, Dict

from dotenv import load_dotenv


def _base64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _build_jwt(secret: str, payload: Dict[str, Any]) -> str:
    header = {"alg": "HS256", "typ": "JWT"}
    header_segment = _base64url_encode(json.dumps(header, separators=(",", ":")).encode("utf-8"))
    payload_segment = _base64url_encode(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    signing_input = f"{header_segment}.{payload_segment}".encode("ascii")
    signature = hmac.new(secret.encode("utf-8"), signing_input, hashlib.sha256).digest()
    signature_segment = _base64url_encode(signature)
    return f"{header_segment}.{payload_segment}.{signature_segment}"


def _load_dotenv() -> None:
    dotenv_path = Path(__file__).resolve().parents[1] / ".env"
    load_dotenv(dotenv_path=dotenv_path, override=False)


def main() -> int:
    _load_dotenv()

    parser = argparse.ArgumentParser(description="Generate an HS256 bearer token for the MCP server.")
    parser.add_argument("--secret", default=os.getenv("MCP_AUTH_SECRET"), help="HS256 secret. Defaults to MCP_AUTH_SECRET.")
    parser.add_argument("--issuer", default=os.getenv("MCP_AUTH_ISSUER", "mcp-issuer"), help="Token issuer.")
    parser.add_argument("--audience", default=os.getenv("MCP_AUTH_AUDIENCE", "azure-ai-search-mcp"), help="Token audience.")
    parser.add_argument("--subject", default="test-user", help="Token subject.")
    parser.add_argument("--ttl-seconds", type=int, default=3600, help="Token lifetime in seconds.")
    parser.add_argument("--raw", action="store_true", help="Print only the JWT instead of a Bearer token.")
    args = parser.parse_args()

    if not args.secret:
        print("MCP_AUTH_SECRET is required. Set it in the environment or pass --secret.", file=sys.stderr)
        return 1

    if args.ttl_seconds <= 0:
        print("--ttl-seconds must be greater than zero.", file=sys.stderr)
        return 1

    now = int(time.time())
    payload = {
        "iss": args.issuer,
        "aud": args.audience,
        "sub": args.subject,
        "iat": now,
        "exp": now + args.ttl_seconds,
    }

    token = _build_jwt(args.secret, payload)
    print(token if args.raw else f"Bearer {token}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())