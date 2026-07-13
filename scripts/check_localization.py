#!/usr/bin/env python3
"""Localization hygiene checks for the Gaurava iOS app target.

Gaurava switches language IN-APP by routing every user-facing string through the
`appLocalized` / `appLocalizedValue` / `appLocalizedResource` helpers (which
resolve against the chosen language's bundle). Raw `String(localized:)` /
`NSLocalizedString(...)` bypass that and silently stop switching — so they are
banned in the app UI. See the "Localization" section of CLAUDE.md.

Modes:
  lint     Fail if app-UI Swift calls String(localized:) / NSLocalizedString
           directly. `Gaurava/SharedSurfaces/**` is exempt (those render in the
           widget / watch / Live-Activity processes and follow their own
           locale). `Gaurava/Design/AppLanguage.swift` is exempt (it defines the
           helpers). Any single line may opt out with a trailing `// i18n:allow`.

  catalog  Report, for Localizable.xcstrings:
             (a) helper string-LITERAL keys used in code but MISSING from the
                 catalog (they would render untranslated in every language), and
             (b) translatable catalog keys missing a value for a target language
                 (the worklist the implementing agent must translate directly).

No subcommand runs both. Exit non-zero on lint violations or on (a). Translation
gaps (b) are reported and only fail the run under --strict.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
APP_DIR = REPO_ROOT / "Gaurava"
CATALOG = APP_DIR / "Resources/Localization/Localizable.xcstrings"

# App-UI Swift, minus the cross-process surfaces and the localization core.
EXCLUDE_DIRS = ("SharedSurfaces",)
EXCLUDE_FILES = ("AppLanguage.swift",)
ALLOW_MARKER = "// i18n:allow"

FORBIDDEN = (
    (re.compile(r"\bString\(localized:"), "String(localized:) — use appLocalizedValue/appLocalizedResource"),
    (re.compile(r"\bNSLocalizedString\("), "NSLocalizedString(...) — use appLocalized"),
)

# appLocalized("literal") / appLocalizedValue("literal") with a plain (non-
# interpolated) string literal. Captures the literal, honoring \" escapes.
HELPER_LITERAL = re.compile(r'\bappLocalized(?:Value)?\(\s*"((?:[^"\\]|\\.)*)"\s*\)')


def app_swift_files() -> list[Path]:
    files: list[Path] = []
    for path in sorted(APP_DIR.rglob("*.swift")):
        rel = path.relative_to(APP_DIR)
        if any(part in EXCLUDE_DIRS for part in rel.parts):
            continue
        if path.name in EXCLUDE_FILES:
            continue
        files.append(path)
    return files


def lint(files: list[Path]) -> list[str]:
    violations: list[str] = []
    for path in files:
        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if ALLOW_MARKER in line:
                continue
            for pattern, message in FORBIDDEN:
                if pattern.search(line):
                    rel = path.relative_to(REPO_ROOT)
                    violations.append(f"{rel}:{lineno}: {message}\n    {line.strip()}")
    return violations


def code_literal_keys(files: list[Path]) -> set[str]:
    keys: set[str] = set()
    for path in files:
        text = path.read_text(encoding="utf-8")
        for match in HELPER_LITERAL.finditer(text):
            literal = match.group(1)
            if "\\(" in literal:  # interpolation — key is a runtime format, skip
                continue
            keys.add(literal.replace('\\"', '"').replace("\\\\", "\\"))
    return keys


def load_catalog() -> dict:
    return json.loads(CATALOG.read_text(encoding="utf-8"))


def unit_value(node: dict) -> str:
    """First concrete value under a localization node (handles plural variations)."""
    if "stringUnit" in node:
        return node["stringUnit"].get("value", "")
    for cases in (node.get("variations") or {}).values():
        for child in cases.values():
            value = unit_value(child)
            if value:
                return value
    return ""


def is_translatable(key: str) -> bool:
    return bool(re.search(r"[A-Za-z]", key))


def catalog_report(files: list[Path], strict: bool) -> tuple[int, list[str]]:
    catalog = load_catalog()
    source = catalog.get("sourceLanguage", "en")
    strings = catalog.get("strings") or {}
    catalog_keys = set(strings)

    # Target languages = every language present anywhere, minus the source.
    targets: set[str] = set()
    for entry in strings.values():
        targets.update((entry.get("localizations") or {}).keys())
    targets.discard(source)
    target_list = sorted(targets)

    out: list[str] = []

    # (a) literal keys used in code but absent from the catalog.
    missing_in_catalog = sorted(code_literal_keys(files) - catalog_keys)
    if missing_in_catalog:
        out.append(f"Keys used in code but MISSING from the catalog ({len(missing_in_catalog)}):")
        out.extend(f"    {key!r}" for key in missing_in_catalog)
        out.append("  → add them to Localizable.xcstrings (then translate), or they render untranslated.")

    # (b) translatable keys missing a target-language value.
    gaps: dict[str, list[str]] = {lang: [] for lang in target_list}
    for key, entry in strings.items():
        if not is_translatable(key):
            continue
        locs = entry.get("localizations") or {}
        for lang in target_list:
            if not unit_value(locs.get(lang) or {}):
                gaps[lang].append(key)
    gap_total = sum(len(v) for v in gaps.values())
    if gap_total:
        out.append(f"Translatable keys missing a value ({gap_total} across {', '.join(target_list)}):")
        for lang in target_list:
            if gaps[lang]:
                out.append(f"    {lang}: {len(gaps[lang])} missing")
        out.append("  → translate these entries directly using repo context and the localization glossary")

    # Informational by default (the catalog may carry a translation backlog);
    # --strict turns any gap into a failure for release/CI gates.
    exit_code = 1 if (strict and (missing_in_catalog or gap_total)) else 0
    return exit_code, out


def cmd_lint(args: argparse.Namespace) -> int:
    violations = lint(app_swift_files())
    if violations:
        print(f"FAIL localization lint — {len(violations)} raw localization call(s) in app UI:\n")
        print("\n".join(violations))
        print("\nUse appLocalized / appLocalizedValue / appLocalizedResource instead")
        print("(or mark an intentional exception with `// i18n:allow`).")
        return 1
    print("OK localization lint — no raw String(localized:)/NSLocalizedString in app UI.")
    return 0


def cmd_catalog(args: argparse.Namespace) -> int:
    exit_code, out = catalog_report(app_swift_files(), args.strict)
    if out:
        print("\n".join(out))
    else:
        print("OK localization catalog — every code key is present and every translatable key is filled.")
    return exit_code


def cmd_all(args: argparse.Namespace) -> int:
    lint_code = cmd_lint(args)
    print()
    catalog_code = cmd_catalog(args)
    return 1 if (lint_code or catalog_code) else 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--strict", action="store_true", help="Also fail on missing translations (mode (b)).")
    parser.set_defaults(func=cmd_all)
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("lint", help="Ban raw localization calls in app UI.").set_defaults(func=cmd_lint)
    cat = sub.add_parser("catalog", help="Report missing keys + untranslated entries.")
    cat.add_argument("--strict", action="store_true", help="Fail on missing translations too.")
    cat.set_defaults(func=cmd_catalog)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
