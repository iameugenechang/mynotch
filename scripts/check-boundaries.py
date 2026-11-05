#!/usr/bin/env python3
"""Temporary source-level guardrails until Swift target boundaries enforce these rules."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
COMPONENT_FILES = (
    "boringNotch/models/OneGoal.swift",
    "boringNotch/models/OneGoalStore.swift",
    "boringNotch/models/OneGoalDependencies.swift",
)
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
            yield number, "platform/UI import in Working on logic"
        if FORBIDDEN.search(code):
            yield number, "concrete adapter or singleton access in Working on logic"


def main():
    errors = []
    for relative in COMPONENT_FILES:
        for number, message in violations((ROOT / relative).read_text()):
            errors.append(f"{relative}:{number}: {message}")
    for path in (ROOT / "boringNotch").rglob("*.swift"):
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if re.search(r"\bOneGoalStore\s*\.\s*shared\b", line.split("//", 1)[0]):
                errors.append(f"{path.relative_to(ROOT)}:{number}: inject the app-owned Working on store")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("Working on boundary checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
