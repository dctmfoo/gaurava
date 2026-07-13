#!/usr/bin/env python3
"""Validate release identifiers, signing contracts, entitlements, and watch icon."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
import plistlib
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TEAM = os.environ.get("APPLE_TEAM_ID", "")
APP_GROUP = "group.com.nags.gaurava"
CLOUDKIT = "iCloud.com.nags.gaurava"
EXPECTED = {
    "app_bundle_id": "com.nags.gaurava",
    "widget_bundle_id": "com.nags.gaurava.GauravaWidgets",
    "watch_bundle_id": "com.nags.gaurava.watchkitapp",
    "watch_widget_bundle_id": "com.nags.gaurava.watchkitapp.GauravaWatchWidgets",
    "release_profile_uuid": "",
    "widget_profile_uuid": "",
    "watch_profile_uuid": "",
    "watch_widget_profile_uuid": "",
}
PROFILE_CONTRACTS = {
    "release_profile_uuid": ("Gaurava App Store AppGroups", "app_bundle_id", True),
    "widget_profile_uuid": ("Gaurava Widgets App Store", "widget_bundle_id", False),
    "watch_profile_uuid": ("Gaurava Watch App Store", "watch_bundle_id", False),
    "watch_widget_profile_uuid": ("Gaurava Watch Widgets App Store", "watch_widget_bundle_id", False),
}
TARGET_CONTRACTS = {
    "Gaurava": {
        "bundle": "app_bundle_id",
        "profile_name": "Gaurava App Store AppGroups",
        "profile_uuid": "release_profile_uuid",
        "entitlements": "CODE_SIGN_ENTITLEMENTS: Gaurava/Gaurava.Release.entitlements",
        "extra": ("ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon",),
    },
    "GauravaWidgets": {
        "bundle": "widget_bundle_id",
        "profile_name": "Gaurava Widgets App Store",
        "profile_uuid": "widget_profile_uuid",
        "entitlements": "CODE_SIGN_ENTITLEMENTS: GauravaWidgets/GauravaWidgets.entitlements",
        "extra": (),
    },
    "GauravaWatch": {
        "bundle": "watch_bundle_id",
        "profile_name": "Gaurava Watch App Store",
        "profile_uuid": "watch_profile_uuid",
        "entitlements": "CODE_SIGN_ENTITLEMENTS: GauravaWatch/GauravaWatch.entitlements",
        "extra": ("ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon", "- path: Gaurava/AppIcon.icon"),
    },
    "GauravaWatchWidgets": {
        "bundle": "watch_widget_bundle_id",
        "profile_name": "Gaurava Watch Widgets App Store",
        "profile_uuid": "watch_widget_profile_uuid",
        "entitlements": "CODE_SIGN_ENTITLEMENTS: GauravaWatchWidgets/GauravaWatchWidgets.entitlements",
        "extra": (),
    },
}


def fail(message: str) -> None:
    print(f"release-config: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_plist(relative: str) -> dict:
    with (ROOT / relative).open("rb") as handle:
        return plistlib.load(handle)


def assert_equal(label: str, actual: str, expected: str) -> None:
    # An empty expected value is "not pinned in the public tree": the real
    # value is maintainer-local (Makefile.local) and only the caller has it.
    if expected == "":
        return
    if actual != expected:
        fail(f"{label} expected {expected!r}, got {actual!r}")


def check_inputs(args: argparse.Namespace) -> None:
    assert_equal("team", args.team, TEAM)
    for key, expected in EXPECTED.items():
        assert_equal(key, getattr(args, key), expected)


def target_block(project: str, target: str) -> str:
    match = re.search(rf"^  {re.escape(target)}:\n(?P<body>.*?)(?=^  \S[^\n]*:\n|\Z)", project, re.MULTILINE | re.DOTALL)
    if match is None:
        fail(f"project.yml is missing target {target}")
    return match.group("body")


def check_project(args: argparse.Namespace) -> None:
    project = (ROOT / "project.yml").read_text(encoding="utf-8")
    for target, contract in TARGET_CONTRACTS.items():
        block = target_block(project, target)
        # Maintainer-local Release signing values (team ID, profile name/UUID)
        # live in gitignored Config/Signing-<Target>.local.xcconfig overlays,
        # pulled in via the tracked per-target xcconfig stubs. The tracked
        # project.yml must wire the stub; the values themselves are enforced
        # against the installed profiles below (check_profiles).
        required = (
            f"PRODUCT_BUNDLE_IDENTIFIER: {getattr(args, contract['bundle'])}",
            f"Release: Config/Signing-{target}.xcconfig",
            "Release:",
            "CODE_SIGN_STYLE: Manual",
            contract["entitlements"],
            *contract["extra"],
        )
        missing = [needle for needle in required if needle not in block]
        if missing:
            fail(f"project.yml target {target} is missing release contracts: {', '.join(missing)}")


def check_entitlements() -> None:
    debug = load_plist("Gaurava/Gaurava.entitlements")
    release = load_plist("Gaurava/Gaurava.Release.entitlements")
    assert_equal("Debug aps-environment", debug.get("aps-environment", ""), "development")
    assert_equal("Release aps-environment", release.get("aps-environment", ""), "production")
    for label, plist in (("Debug app", debug), ("Release app", release)):
        if CLOUDKIT not in plist.get("com.apple.developer.icloud-container-identifiers", []):
            fail(f"{label} entitlements omit {CLOUDKIT}")
        if APP_GROUP not in plist.get("com.apple.security.application-groups", []):
            fail(f"{label} entitlements omit {APP_GROUP}")
        if plist.get("com.apple.developer.healthkit") is not True:
            fail(f"{label} entitlements omit HealthKit")
    for relative in (
        "GauravaWidgets/GauravaWidgets.entitlements",
        "GauravaWatch/GauravaWatch.entitlements",
        "GauravaWatchWidgets/GauravaWatchWidgets.entitlements",
    ):
        if APP_GROUP not in load_plist(relative).get("com.apple.security.application-groups", []):
            fail(f"{relative} omits {APP_GROUP}")


def check_icon_source() -> None:
    icon = json.loads((ROOT / "Gaurava/AppIcon.icon/icon.json").read_text(encoding="utf-8"))
    circles = icon.get("supported-platforms", {}).get("circles", [])
    if "watchOS" not in circles:
        fail("shared AppIcon.icon does not declare watchOS circle support")
    info = load_plist("GauravaWatch/Info.plist")
    assert_equal("watch CFBundleIconName", info.get("CFBundleIconName", ""), "AppIcon")


def check_profiles(args: argparse.Namespace) -> None:
    profile_dir = Path.home() / "Library/MobileDevice/Provisioning Profiles"
    now = datetime.now(timezone.utc)
    for key, (name, bundle_key, is_app) in PROFILE_CONTRACTS.items():
        uuid = getattr(args, key)
        path = profile_dir / f"{uuid}.mobileprovision"
        if not path.is_file():
            fail(f"installed profile missing: {path}")
        decoded = subprocess.run(
            ["security", "cms", "-D", "-i", str(path)], check=True, capture_output=True
        ).stdout
        profile = plistlib.loads(decoded)
        assert_equal(f"{key} UUID", profile.get("UUID", ""), uuid)
        assert_equal(f"{key} name", profile.get("Name", ""), name)
        expiration = profile.get("ExpirationDate")
        if not isinstance(expiration, datetime) or expiration.replace(tzinfo=timezone.utc) <= now:
            fail(f"{key} is expired or has no valid ExpirationDate")
        entitlements = profile.get("Entitlements") or {}
        bundle_id = getattr(args, bundle_key)
        # Team comes from the caller (Makefile.local); TEAM env is unset in the
        # public tree. Guard so an empty team never degrades these checks.
        team = args.team or TEAM
        if team:
            assert_equal(f"{key} application identifier", entitlements.get("application-identifier", ""), f"{team}.{bundle_id}")
            assert_equal(f"{key} team identifier", entitlements.get("com.apple.developer.team-identifier", ""), team)
        if entitlements.get("get-task-allow") is not False:
            fail(f"{key} is not an App Store distribution profile")
        if APP_GROUP not in entitlements.get("com.apple.security.application-groups", []):
            fail(f"{key} omits {APP_GROUP}")
        if is_app:
            assert_equal(f"{key} aps-environment", entitlements.get("aps-environment", ""), "production")
            if CLOUDKIT not in entitlements.get("com.apple.developer.icloud-container-identifiers", []):
                fail(f"{key} omits {CLOUDKIT}")
            if entitlements.get("com.apple.developer.healthkit") is not True:
                fail(f"{key} omits HealthKit")


def check_built_watch_app(path: Path) -> None:
    if not path.is_dir():
        fail(f"built watch app not found: {path}")
    info_path = path / "Info.plist"
    assets_path = path / "Assets.car"
    if not info_path.is_file() or not assets_path.is_file():
        fail(f"built watch app is missing Info.plist or Assets.car: {path}")
    with info_path.open("rb") as handle:
        info = plistlib.load(handle)
    assert_equal("built watch CFBundleIconName", info.get("CFBundleIconName", ""), "AppIcon")
    result = subprocess.run(
        ["xcrun", "assetutil", "--info", str(assets_path)], check=True, capture_output=True, text=True
    ).stdout
    records = json.loads(result)
    icons = [
        item for item in records
        if item.get("AssetType") == "Icon Image"
        and item.get("Name") == "AppIcon"
        and item.get("Idiom") == "watch"
    ]
    if not icons:
        fail("built watch Assets.car does not contain a watch Icon Image named AppIcon")
    if not any(
        item.get("Opaque") is True
        and item.get("PixelWidth", 0) >= 1024
        and item.get("PixelHeight", 0) >= 1024
        for item in icons
    ):
        fail("built watch AppIcon is not an opaque 1024x1024 icon")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--built-watch-app", type=Path)
    parser.add_argument("--team", required=True)
    for key in EXPECTED:
        parser.add_argument("--" + key.replace("_", "-"), dest=key, required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    check_inputs(args)
    check_project(args)
    check_entitlements()
    check_icon_source()
    if not args.dry_run:
        check_profiles(args)
        if args.built_watch_app is None:
            fail("full validation requires --built-watch-app")
        check_built_watch_app(args.built_watch_app)
    print(f"release-config: {'static dry-run' if args.dry_run else 'full'} validation passes")


if __name__ == "__main__":
    main()
