#!/usr/bin/env python3
"""Route only this review invocation through the existing local Raven provider.

Keep CODEX_HOME, model, tools and review policy separate from daily Codex.
Never load auth files, print credential values, edit configuration or retry.
"""
import json
import os
from pathlib import Path
import shutil
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
    providers = config.get("model_providers", {})
    if not isinstance(providers, dict) or not isinstance(providers.get("raven"), dict):
        raise ValueError("Raven provider must be a configuration table")
    provider = providers["raven"]
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


def review_environment(environment, config_path):
    # Only the explicit review override is trusted, never an inherited daily CODEX_HOME.
    home = Path(environment.get("CODEX_REVIEW_HOME") or Path.home() / ".codex-review")
    try:
        home = home.expanduser().resolve()
        daily_homes = {(Path.home() / ".codex").resolve(), Path(config_path).expanduser().resolve().parent}
    except (OSError, RuntimeError, ValueError):
        raise ValueError("Cannot resolve review home or provider configuration location") from None
    if home in daily_homes:
        raise ValueError("Review home must be separate from daily provider configuration")
    return dict(environment, CODEX_HOME=str(home))


def main():
    arguments = sys.argv[1:]
    setup_only = bool(arguments and arguments[0] == "--check-setup")
    if setup_only:
        arguments = arguments[1:]
    if not arguments or (setup_only and len(arguments) != 1):
        print("[codex-review] expected [--check-setup] Codex binary; exec arguments only in review mode",
              file=sys.stderr)
        return 1
    config = os.environ.get("CODEX_RAVEN_CONFIG", str(Path.home() / ".codex/config.toml"))
    try:
        environment = review_environment(os.environ, config)
        command = build_command(config, arguments[0], arguments[1:], environment)
        binary = shutil.which(command[0])
        if binary is None:
            raise ValueError("Codex executable is unavailable; check runner PATH or CODEX_BIN")
        if setup_only:
            print("[codex-review] Raven setup PASS (metadata, environment, binary, home isolation only); "
                  "no model request, profile validation, verdict or merge verification")
            return 0
        os.execvpe(binary, command, environment)
    except (ValueError, OSError) as error:
        # Never print an OSError filename/argv or a TOML parser's source excerpt.
        detail = str(error) if isinstance(error, ValueError) else "Cannot start Codex executable"
        print(f"[codex-review] Raven setup failed: {detail}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
