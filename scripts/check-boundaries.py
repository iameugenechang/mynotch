#!/usr/bin/env python3
"""Check the package dependency graph and rules Swift targets cannot enforce alone."""
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "Packages/AnotchupFeatures"
ALLOWED_IMPORTS = {"Foundation", "Combine"}
FORBIDDEN = re.compile(
    r"\b(UserDefaults|Timer|RunLoop|UserDefaultsOneGoalPersistence|RunLoopCountdownScheduler)\b"
    r"|\.shared\b"
)


def violations(source):
    for number, line in enumerate(source.splitlines(), 1):
        code = line.split("//", 1)[0]
        imported = re.search(r"\bimport\s+(\w+)", code)
        if imported and imported.group(1) not in ALLOWED_IMPORTS:
            yield number, "platform/UI/adapter import in Working on logic"
        if FORBIDDEN.search(code):
            yield number, "concrete adapter or singleton access in Working on logic"


def graph_violations(manifest):
    targets = {target["name"]: target for target in manifest["targets"]}
    expected = {"WorkingOn": [], "WorkingOnAdapters": ["WorkingOn"]}
    for name, dependencies in expected.items():
        target = targets.get(name)
        if target is None:
            yield f"missing target {name}"
            continue
        actual = target["dependencies"]
        if actual != [{"byName": [dependency, None]} for dependency in dependencies]:
            yield f"{name} must depend only on {dependencies}"
        if target.get("path") not in (None, f"Sources/{name}"):
            yield f"{name} sources must stay in their own target directory"
        if target.get("settings"):
            yield f"review {name} build settings before adding them to this boundary"


def main():
    errors = []
    manifest = json.loads(subprocess.check_output(
        ["xcrun", "swift", "package", "--package-path", str(PACKAGE), "dump-package"], text=True
    ))
    errors.extend(f"Packages/AnotchupFeatures/Package.swift: {error}" for error in graph_violations(manifest))
    sources = list((PACKAGE / "Sources/WorkingOn").rglob("*.swift"))
    if not sources:
        errors.append("WorkingOn has no Swift sources")
    for path in sources:
        for number, message in violations(path.read_text()):
            errors.append(f"{path.relative_to(ROOT)}:{number}: {message}")
    for path in (ROOT / "boringNotch").rglob("*.swift"):
        for number, line in enumerate(path.read_text().splitlines(), 1):
            code = line.split("//", 1)[0]
            if re.search(r"\bOneGoalStore\s*\.\s*shared\b", code):
                errors.append(f"{path.relative_to(ROOT)}:{number}: inject the app-owned Working on store")
            if re.search(r"\b(class|struct|enum|protocol)\s+(OneGoal|OneGoalStore|OneGoalEditorSession|OneGoalPersistence|CountdownScheduling)\b", code):
                errors.append(f"{path.relative_to(ROOT)}:{number}: use the package implementation, not an app copy")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("Working on package and source boundary checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
