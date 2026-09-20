#!/usr/bin/env python3
"""Route only this review invocation through the existing local Raven provider.

Keep CODEX_HOME, model, tools and review policy separate from daily Codex.
Never load auth files, print credential values, edit configuration or retry.
"""
import json
import os
from pathlib import Path
import sys
import tomllib
from urllib.parse import urlsplit


def build_command(config_path, binary, arguments, environment):
    try:
        config = tomllib.loads(Path(config_path).read_text())
    except (OSError, UnicodeError, tomllib.TOMLDecodeError):
        raise ValueError("Cannot read daily Codex provider configuration") from None
    if config.get("model_provider") != "raven":
        raise ValueError("Daily Codex must explicitly select the Raven provider")
    provider = config.get("model_providers", {}).get("raven", {})
    endpoint = provider.get("base_url")
    key_name = provider.get("env_key")
    if not isinstance(endpoint, str) or not isinstance(key_name, str):
        raise ValueError("Raven base_url and credential environment name are required")
    try:
        url = urlsplit(endpoint)
        local = url.hostname in {"localhost", "127.0.0.1", "::1"} and url.port is not None
    except ValueError:
        raise ValueError("Invalid local Raven endpoint") from None
    if (url.scheme not in {"http", "https"} or not local or url.username is not None
            or url.password is not None or url.query or url.fragment):
        raise ValueError("Raven endpoint must be local and contain no authentication data")
    if provider.get("wire_api") != "responses" or provider.get("requires_openai_auth", False) is not False:
        raise ValueError("Raven must use Responses without OpenAI account authentication")
    # Raven's existing supported names only; never select unrelated CI secrets.
    if key_name not in {"OPENAI_API_KEY", "RAVEN_API_KEY"}:
        raise ValueError("Unsupported Raven credential environment name")
    if not environment.get(key_name):
        raise ValueError(f"Runner is missing Raven environment variable {key_name}; no direct fallback")
    # A complete inline provider replaces any stale review-home Raven definition.
    # JSON string escaping is compatible with TOML basic strings; no shell eval.
    fields = {"name": "raven", "base_url": endpoint, "wire_api": "responses", "env_key": key_name}
    table = "{ " + ", ".join(f"{key} = {json.dumps(value)}" for key, value in fields.items())
    table += ", requires_openai_auth = false }"
    return [binary, "exec", "-c", 'model_provider="raven"',
            "-c", "model_providers.raven=" + table, *arguments]


def main():
    if len(sys.argv) < 2:
        print("[codex-review] expected Codex binary and exec arguments", file=sys.stderr)
        return 1
    config = os.environ.get("CODEX_RAVEN_CONFIG", str(Path.home() / ".codex/config.toml"))
    try:
        command = build_command(config, sys.argv[1], sys.argv[2:], os.environ)
        os.execvp(command[0], command)
    except (ValueError, OSError) as error:
        # Never print an OSError filename/argv or a TOML parser's source excerpt.
        detail = str(error) if isinstance(error, ValueError) else "Cannot start Codex executable"
        print(f"[codex-review] Raven setup failed: {detail}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
