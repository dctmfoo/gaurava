#!/usr/bin/env python3
"""Mechanical checks for Gaurava's repo-level agent contracts."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VALID_STATUSES = {"Draft", "Ready", "Implemented"}
REQUIRED_DOCS = ("PRD.md", "DESIGN.md", "PLAN.md")
REQUIRED_SPEC_SECTIONS = tuple(f"## {number}." for number in range(1, 9))
MILESTONE_STATUS = re.compile(r"^(?:not started|in progress|gate passed \d{4}-\d{2}-\d{2} \([0-9a-f]{7,40}\))$")


def fail(message: str) -> None:
    print(f"process-check: {message}", file=sys.stderr)
    raise SystemExit(1)


def require_file(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file():
        fail(f"missing required file: {relative}")
    return path.read_text(encoding="utf-8")


def check_specs() -> None:
    specs = sorted((ROOT / "docs/specs").glob("SPEC-*.md"))
    if not specs:
        fail("docs/specs contains no SPEC-*.md files")

    for path in specs:
        text = path.read_text(encoding="utf-8")
        status = re.search(r"^\*\*Status:\*\* (\S+)$", text, re.MULTILINE)
        if status is None or status.group(1) not in VALID_STATUSES:
            fail(f"{path.relative_to(ROOT)} has no valid Status line")
        for header in ("**Owner screens/logic:**", "**Docs this spec amends:**", "**Branch:**"):
            if header not in text:
                fail(f"{path.relative_to(ROOT)} is missing {header}")
        for section in REQUIRED_SPEC_SECTIONS:
            if section not in text:
                fail(f"{path.relative_to(ROOT)} is missing section {section}")
        decisions = list(re.finditer(r"^### D\d+\b.*$", text, re.MULTILINE))
        for index, decision in enumerate(decisions):
            end = decisions[index + 1].start() if index + 1 < len(decisions) else len(text)
            if "**Contract grounding:**" not in text[decision.end():end]:
                fail(f"{path.relative_to(ROOT)} decision {decision.group(0)} lacks Contract grounding")


def check_prd() -> None:
    prd = require_file("PRD.md")
    for header in ("**Version:**", "**Date:**", "**Status:**", "**Audience:**", "## Changelog"):
        if header not in prd:
            fail(f"PRD.md is missing {header}")

    models = require_file("Gaurava/Models/TrackerModels.swift")
    model_names = re.findall(r"@Model\s+final class (\w+)", models)
    missing_models = [name for name in model_names if name not in prd]
    if missing_models:
        fail(f"PRD.md omits shipped models: {', '.join(missing_models)}")

    missing_tabs = [name for name in ("Summary", "Jabs", "Results", "Log", "Care") if name not in prd]
    if missing_tabs:
        fail(f"PRD.md omits shipped tabs: {', '.join(missing_tabs)}")


def check_plan() -> None:
    plan = require_file("PLAN.md")
    milestones = list(re.finditer(r"^## Milestone \d+.*$", plan, re.MULTILINE))
    if not milestones:
        fail("PLAN.md has no milestone")
    for index, milestone in enumerate(milestones):
        end = milestones[index + 1].start() if index + 1 < len(milestones) else len(plan)
        block = plan[milestone.end():end]
        for label in ("**Scope:**", "**Verify:**", "**Gate:**", "**Status:**"):
            if block.count(label) != 1:
                fail(f"{milestone.group(0)} must carry exactly one {label}")
        status = re.search(r"^\*\*Status:\*\* (.+)$", block, re.MULTILINE)
        if status is None or MILESTONE_STATUS.fullmatch(status.group(1)) is None:
            fail(f"{milestone.group(0)} has invalid Status")


def main() -> None:
    for relative in REQUIRED_DOCS:
        require_file(relative)
    if (ROOT / "CLAUDE.md").read_bytes() != (ROOT / "AGENTS.md").read_bytes():
        fail("CLAUDE.md and AGENTS.md are not byte-identical")
    check_specs()
    check_prd()
    check_plan()
    print("process-check: canonical docs, spec lifecycle, PRD coverage, and mirror contract pass")


if __name__ == "__main__":
    main()
