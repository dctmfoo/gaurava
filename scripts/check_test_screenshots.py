#!/usr/bin/env python3
"""Keep screenshot-producing tests out of the default correctness gate."""

from __future__ import annotations

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]

SCAN_ROOTS = [
    ROOT / "GauravaTests",
    ROOT / "GauravaUITests",
    ROOT / "GauravaSurfaceSnapshots",
]

APPROVED_CAPTURE_FILES = {
    Path("GauravaUITests/LocalizedScreenshotAuditUITests.swift"),
    Path("GauravaUITests/MarketingScreenshotTests.swift"),
    Path("GauravaUITests/SemaglutideVerificationScreenshotTests.swift"),
    Path("GauravaSurfaceSnapshots/SurfaceSnapshotTests.swift"),
}

SCREENSHOT_PATTERNS = (
    "XCTAttachment(screenshot:",
    "XCUIScreen.main.screenshot",
    ".screenshot()",
    ".keepAlways",
)


def rel(path: Path) -> Path:
    return path.relative_to(ROOT)


def main() -> int:
    missing = sorted(path for path in APPROVED_CAPTURE_FILES if not (ROOT / path).exists())
    if missing:
        print("Screenshot policy checker is stale; approved files are missing:", file=sys.stderr)
        for path in missing:
            print(f"  {path}", file=sys.stderr)
        return 2

    violations: list[tuple[Path, int, str, str]] = []
    for root in SCAN_ROOTS:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.swift")):
            relative = rel(path)
            approved = relative in APPROVED_CAPTURE_FILES
            for line_number, line in enumerate(path.read_text().splitlines(), start=1):
                for pattern in SCREENSHOT_PATTERNS:
                    if pattern in line and not approved:
                        violations.append((relative, line_number, pattern, line.strip()))

    if violations:
        print("Screenshot policy violation: screenshot artifacts are only allowed in approved capture files.", file=sys.stderr)
        for path, line_number, pattern, line in violations:
            print(f"  {path}:{line_number}: {pattern}: {line}", file=sys.stderr)
        print("\nApproved capture files:", file=sys.stderr)
        for path in sorted(APPROVED_CAPTURE_FILES):
            print(f"  {path}", file=sys.stderr)
        return 1

    print("Screenshot policy OK: screenshot-producing APIs are confined to approved capture files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
