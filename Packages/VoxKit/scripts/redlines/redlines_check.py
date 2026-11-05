#!/usr/bin/env python3
"""Deterministic VoxKit red-line scanner and fixture harness."""
from __future__ import annotations
import argparse, json, re, subprocess, sys
from pathlib import Path

R1_PATTERNS = [
    r"ProcessInfo", r"\bgetenv\(", r"\bsetenv\(", r"environment\[", r"UserDefaults", r"@AppStorage",
    r"CFPreferences", r"NSUbiquitousKeyValueStore", r"Bundle\.main", r"Bundle\(for:", r"infoDictionary",
    r"SecItem", r"Data\(contentsOf:", r"String\(contentsOf", r"contentsOfFile", r"NSDictionary\(contentsOf:",
    r"FileHandle\(forReading", r"InputStream\(", r"\.urls?\(for:", r"contents\(atPath:",
    r"contentsOfDirectory", r"applicationSupportDirectory", r"cachesDirectory", r"documentDirectory",
    r"homeDirectory", r"NSHomeDirectory", r"NSTemporaryDirectory", r"temporaryDirectory", r"CommandLine",
    r"environ\b", r"URL\(fileURLWithPath:",
]
R4_TYPES = re.compile(r"\b(?:Publisher|AnyPublisher|PassthroughSubject|CurrentValueSubject|Subject|Cancellable|AnyCancellable)\b")
R5_PRODUCT = re.compile(r"VoxPocket|MY-[0-9]+|com\.leepepe", re.I)
R5_GUID = re.compile(r"\b[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\b")
R5_HOST = re.compile(r"\b([A-Za-z0-9_-]+)\.(services\.ai|openai|cognitiveservices)\.azure\.com\b", re.I)
ALLOW_R1 = {"TemporaryAudioStore.swift", "WhisperKitModelCacheAdapter.swift"}


def swift_files(paths: list[Path]):
    for path in paths:
        if path.is_file() and path.suffix == ".swift": yield path
        elif path.is_dir(): yield from sorted(path.rglob("*.swift"))


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//.*", "", text)


def scan_rule(rule: str, paths: list[Path]) -> list[str]:
    findings: list[str] = []
    for path in swift_files(paths):
        raw = path.read_text(encoding="utf-8")
        text = strip_comments(raw)
        lines = raw.splitlines()
        if rule == "R1":
            for i, line in enumerate(lines, 1):
                if path.name in ALLOW_R1 and "redline-allow: R1" in line:
                    continue
                if any(re.search(p, line) for p in R1_PATTERNS): findings.append(f"{path}:{i}:{line.strip()}")
        elif rule == "R2":
            for i, line in enumerate(lines, 1):
                if re.search(r"import\s+(?:LokiKit|SharedTelemetry|\w*Telemetry\w*)", line): findings.append(f"{path}:{i}:{line.strip()}")
        elif rule == "R3b":
            for i, line in enumerate(lines, 1):
                if re.search(r"\b(?:print|debugPrint|dump)\(|NSLog|os_log|import\s+OSLog|Logger\(subsystem", line): findings.append(f"{path}:{i}:{line.strip()}")
        elif rule == "R4a":
            for i, line in enumerate(lines, 1):
                if re.search(r"import\s+Combine", line): findings.append(f"{path}:{i}:{line.strip()}")
        elif rule == "R5":
            for i, line in enumerate(lines, 1):
                if R5_PRODUCT.search(line) or R5_GUID.search(line): findings.append(f"{path}:{i}:{line.strip()}")
                for host in R5_HOST.finditer(line):
                    if not host.group(1).lower().startswith("example"):
                        findings.append(f"{path}:{i}:{line.strip()}")
        elif rule == "R4b":
            # Inspect declaration text rather than matching ordinary return arrows.
            declarations = re.findall(r"\b(?:public|open)\b[^{};\n]*(?:\n[^{};\n]*)*(?:\{|;|$)", text)
            for declaration in declarations:
                if R4_TYPES.search(declaration): findings.append(f"{path}:public API uses forbidden reactive type")
                if re.search(r"\b(?:func|init|subscript)\b[^\n{]*\([^\n{]*(?:->|@escaping)[^\n{]*\)", declaration, re.S): findings.append(f"{path}:public API uses closure parameter")
                if re.search(r"\b(?:var|let)\b[^\n{]*:\s*[^\n{;]*(?:->|@escaping)", declaration): findings.append(f"{path}:public API uses closure property")
                if re.search(r"\)\s*(?:async\s*)?(?:throws\s*)?->\s*[^\n{;]*(?:->|@escaping)", declaration): findings.append(f"{path}:public API uses closure return")
            protocols = re.findall(r"\bpublic\s+protocol\b.*?(?=\bpublic\s+protocol\b|\Z)", text, re.S)
            for protocol in protocols:
                if re.search(r"\{\s*get\s+set\s*\}|\bfunc\s+set\w*\s*\(", protocol): findings.append(f"{path}:public protocol has mutable setter")
    return findings


def compile_fixture(path: Path, modules: Path) -> tuple[int, str]:
    result = subprocess.run(["xcrun", "swiftc", "-typecheck", "-swift-version", "6", "-I", str(modules), str(path)], text=True, capture_output=True)
    return result.returncode, result.stdout + result.stderr


def build_modules(root: Path) -> Path:
    subprocess.run(["swift", "build", "--package-path", str(root), "--target", "VoxCore"], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    bin_path = subprocess.check_output(["swift", "build", "--package-path", str(root), "--show-bin-path"], text=True).strip()
    modules = Path(bin_path) / "Modules"
    if not modules.is_dir() and (Path(bin_path) / "VoxCore.swiftmodule").exists():
        modules = Path(bin_path)
    if not modules.is_dir():
        candidates = sorted(Path(bin_path).parents[1].glob("**/Modules"))
        modules = next((candidate for candidate in candidates if (candidate / "VoxCore.swiftmodule").exists()), modules)
    if not modules.is_dir(): raise RuntimeError(f"missing VoxCore modules directory: {modules}")
    return modules


def run_checks(root: Path, paths: list[Path]) -> int:
    failed = False
    for rule in ("R1", "R2", "R3b", "R4a", "R4b", "R5"):
        findings = scan_rule(rule, paths)
        if findings:
            print(f"{rule} violation:")
            print("\n".join(findings))
            failed = True
    deps = subprocess.run(["swift", "package", "--package-path", str(root), "show-dependencies", "--format", "json"], text=True, capture_output=True)
    if deps.returncode == 0 and re.search(r"LokiKit|SharedTelemetry", deps.stdout, re.I):
        print("R2 dependency closure contains forbidden telemetry package"); failed = True
    return 1 if failed else 0


def self_test(root: Path) -> int:
    modules = build_modules(root)
    for rule in ("R1", "R2", "R3b", "R4a", "R4b", "R5"):
        bad = root / "scripts/redlines/fixtures/violations" / rule / "violation.swift"
        good = root / "scripts/redlines/fixtures/ok" / rule / "ok.swift"
        if scan_rule(rule, [bad]) == [] or scan_rule(rule, [good]) != []:
            print(f"fixture self-test failed: {rule}"); return 1
        print(f"self-test {rule}: pass")
    bad = root / "scripts/redlines/fixtures/violations/R3a/violation.swift"
    good = root / "scripts/redlines/fixtures/ok/R3a/ok.swift"
    expected = bad.read_text(encoding="utf-8").splitlines()[0].removeprefix("// expected-diagnostic:").strip()
    bad_code, bad_output = compile_fixture(bad, modules)
    good_code, good_output = compile_fixture(good, modules)
    if bad_code == 0 or not re.search(expected, bad_output) or good_code != 0:
        print(f"compile fixture self-test failed: R3a\\n{bad_output}\\n{good_output}"); return 1
    print("self-test R3a compile: pass")
    return run_checks(root, [root / "Sources"])


def generate_baseline(root: Path) -> int:
    infra = root.parent / "VoxInfrastructure"
    source_roots = [infra / "Sources/TranscriptionKit", infra / "Sources/LLMKit"]
    test_root = infra / "Tests"
    inventory: list[dict[str, object]] = []
    task_map = {"T107": [], "T108": [], "T108a": [], "T109": [], "T110": [], "T111": []}
    next_id = 1
    for rule in ("R1", "R2", "R3b", "R4a", "R4b", "R5"):
        findings = scan_rule(rule, source_roots + [test_root])
        for finding in findings:
            parts = finding.split(":", 2)
            if len(parts) == 3:
                path_text, line_text, detail = parts
            else:
                path_text, detail = parts
                line_text = "unknown"
            rule_name = "R3" if rule == "R3b" else ("R4" if rule == "R4a" or rule == "R4b" else rule)
            task = "T107" if rule_name == "R2" else "T109" if rule_name == "R1" else "T110" if rule_name == "R4" else "T108"
            if "GuidedGenerationTests.swift" in path_text: task = "T108a"
            if "requestRecordPermission" in detail or "MicrophoneRecorder.swift" in path_text and rule_name == "R1": task = "T111"
            rel = str(Path(path_text).resolve().relative_to(infra.resolve()))
            item = {"id": f"{rule_name}-{next_id:03d}", "rule": rule_name, "path": rel, "line": int(line_text) if line_text.isdigit() else line_text, "detail": detail, "task": task}
            inventory.append(item); task_map[task].append(item["id"]); next_id += 1
    sendable: dict[str, dict[str, object]] = {}
    for target, roots in {"VoxSpeech": [infra / "Sources/TranscriptionKit"], "VoxSpeechWhisperKit": [infra / "Sources/TranscriptionKit"], "VoxLLM": [infra / "Sources/LLMKit"], "VoxRefine": [infra / "Sources/LLMKit"]}.items():
        occurrences = []
        for path in swift_files(roots):
            if target == "VoxSpeechWhisperKit" and path.name not in {"WhisperKitTranscriber.swift", "HybridLocalWhisperTranscriber.swift", "LoadingFallbackTranscriptionCoordinator.swift"}: continue
            if target == "VoxSpeech" and path.name in {"WhisperKitTranscriber.swift", "HybridLocalWhisperTranscriber.swift", "LoadingFallbackTranscriptionCoordinator.swift"}: continue
            if target == "VoxLLM" and "/Models/" in str(path): continue
            if target == "VoxRefine" and "/Models/" not in str(path): continue
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                for match in re.finditer(r"@unchecked\s+Sendable|nonisolated\(unsafe\)", line): occurrences.append({"path": str(path.resolve().relative_to(infra.resolve())), "line": number, "kind": match.group(0)})
        sendable[target] = {"count": len(occurrences), "target_count_after_T110": 0 if target == "VoxSpeechWhisperKit" else len(occurrences), "occurrences": occurrences}
    baseline = {"schema": 2, "scope": ["Packages/VoxInfrastructure/Sources/TranscriptionKit", "Packages/VoxInfrastructure/Sources/LLMKit", "Packages/VoxInfrastructure/Tests"], "generated_from": "origin/main", "rules": ["R1", "R2", "R3", "R4", "R5", "Sendable"], "sendable_baseline": sendable, "violations": inventory, "task_mapping": task_map}
    (root / "scripts/redlines/pre-migration-baseline.json").write_text(json.dumps(baseline, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--write-baseline", action="store_true")
    parser.add_argument("paths", nargs="*", type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    if args.write_baseline: return generate_baseline(root)
    if args.self_test: return self_test(root)
    paths = [p if p.is_absolute() else root / p for p in (args.paths or [root / "Sources", root / "Tests"])]
    return run_checks(root, paths)

if __name__ == "__main__": sys.exit(main())
