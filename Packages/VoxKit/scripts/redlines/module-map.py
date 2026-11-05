#!/usr/bin/env python3
"""Validate complete staged module ownership, dependency closure and explicit imports."""
from __future__ import annotations
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
MAP = Path(__file__).with_name("module-map.json")
SOURCE = ROOT / "Packages/VoxInfrastructure/Sources"


def code(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r'""".*?"""', '""', text, flags=re.S)
    text = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
    return re.sub(r"//[^\n]*", "", text)


def validate(data: dict, source: Path = SOURCE, root: Path = ROOT) -> int:
    modules = data["modules"]
    seen: dict[Path, str] = {}
    closure: dict[str, set[str]] = {}
    visiting: set[str] = set()

    def dependencies(module: str) -> set[str]:
        if module not in modules:
            raise ValueError(f"unknown dependency: {module}")
        if module in visiting:
            raise ValueError(f"cyclic dependency at {module}")
        if module not in closure:
            visiting.add(module)
            result = {module}
            for dependency in modules[module].get("depends_on", []):
                result |= dependencies(dependency)
            visiting.remove(module)
            closure[module] = result
        return closure[module]

    for module, entry in modules.items():
        dependencies(module)
        for relative in entry["files"]:
            path = source / relative
            if path in seen:
                raise ValueError(f"duplicate mapping: {relative}")
            if not path.is_file():
                raise ValueError(f"missing mapped file: {relative}")
            seen[path] = module
    actual = {path for kit in ("TranscriptionKit", "LLMKit") for path in (source / kit).rglob("*.swift")}
    if actual != set(seen):
        raise ValueError(f"incomplete coverage: missing={sorted(str(p) for p in actual - set(seen))}; extra={sorted(str(p) for p in set(seen) - actual)}")
    native = {path: "VoxCore" for directory in modules["VoxCore"].get("native", [])
              for path in (root / directory).rglob("*.swift")}
    owners: dict[str, str] = {}
    declaration = r"^(?:(?:public|package|internal|private|fileprivate|final|indirect|nonisolated)\s+)*(?:enum|struct|class|actor|protocol|typealias|func)\s+(\w+)"
    for path, module in {**seen, **native}.items():
        for symbol in re.findall(declaration, code(path.read_text()), re.M):
            previous = owners.get(symbol)
            if previous is not None and previous != module:
                raise ValueError(f"ambiguous symbol ownership: {symbol}")
            owners[symbol] = module
    files = set(seen) | set(native) | set((source / "TranscriptionKitCombine").rglob("*.swift"))
    files |= set((source.parent / "Tests").rglob("*.swift"))
    for path in sorted(files):
        text = code(path.read_text())
        if seen.get(path) == "VoxSpeechWhisperKit" and re.search(r"@unchecked\s+Sendable|nonisolated\(unsafe\)", text):
            raise ValueError(f"{path.relative_to(root)}: WhisperKit requires checked isolation")
        used = {owners[token] for token in re.findall(r"\b[A-Za-z_]\w*\b", text) if token in owners}
        imports = set(re.findall(r"^\s*(?:@testable\s+)?import\s+(\w+)", text, re.M))
        current = seen.get(path, native.get(path))
        if current and not used <= closure[current]:
            raise ValueError(f"{path.relative_to(root)}: forbidden module references {sorted(used - closure[current])}")
        if path not in native and "VoxCore" in used and "VoxCore" not in imports:
            raise ValueError(f"{path.relative_to(root)}: missing pre-staged import VoxCore")
        if path.parent.name == "TranscriptionKitCombine" or (current in {"VoxLLM", "VoxRefine"}):
            if used & {"VoxSpeech", "VoxSpeechWhisperKit"} and "TranscriptionKit" not in imports:
                raise ValueError(f"{path.relative_to(root)}: missing import TranscriptionKit")
        for imported in imports & set(modules):
            if current and imported not in closure[current]:
                raise ValueError(f"{path.relative_to(root)}: forbidden import {imported}")
    print(f"module-map: PASS ({len(seen)}/{len(actual)} files; acyclic dependencies; source/test imports)")
    return 0


def main() -> int:
    try:
        return validate(json.loads(MAP.read_text()))
    except (ValueError, KeyError) as error:
        print(f"module-map: FAIL: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
