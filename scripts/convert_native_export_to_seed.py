#!/usr/bin/env python3
"""Convert a native Gaurava data export into the seed-import envelope."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


def stable_id(record: dict[str, Any]) -> str:
    return str(record.get("legacyServerId") or record["id"])


def decimal_string(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return format(value, ".15g")
    return str(value)


def put(target: dict[str, Any], key: str, value: Any) -> None:
    if value is not None:
        target[key] = value


def base_record(record: dict[str, Any]) -> dict[str, Any]:
    converted = {"id": stable_id(record)}
    put(converted, "user_id", record.get("sourceUserId"))
    put(converted, "created_at", record.get("createdAt"))
    put(converted, "updated_at", record.get("updatedAt"))
    return converted


def convert_profile(record: dict[str, Any]) -> dict[str, Any]:
    converted = base_record(record)
    put(converted, "age", record.get("age"))
    put(converted, "gender", record.get("gender"))
    put(converted, "height_cm", decimal_string(record.get("heightCm")))
    put(converted, "starting_weight_kg", decimal_string(record.get("startingWeightKg")))
    put(converted, "goal_weight_kg", decimal_string(record.get("goalWeightKg")))
    put(converted, "treatment_start_date", record.get("treatmentStartDate"))
    put(converted, "medication", record.get("medication"))
    put(converted, "planned_dose_mg", decimal_string(record.get("plannedDoseMg")))
    put(converted, "planned_dose_updated_at", record.get("plannedDoseUpdatedAt"))
    put(converted, "preferred_injection_day", record.get("preferredInjectionDay"))
    put(converted, "reminder_days_before", record.get("reminderDaysBefore"))
    return converted


def convert_preference(record: dict[str, Any]) -> dict[str, Any]:
    converted = base_record(record)
    put(converted, "weight_unit", record.get("weightUnit"))
    put(converted, "height_unit", record.get("heightUnit"))
    put(converted, "date_format", record.get("dateFormat"))
    put(converted, "week_starts_on", record.get("weekStartsOn"))
    put(converted, "theme", record.get("theme"))
    put(converted, "preferred_injection_sites", record.get("preferredInjectionSites"))
    return converted


def convert_weight(record: dict[str, Any]) -> dict[str, Any]:
    converted = base_record(record)
    put(converted, "weight_kg", decimal_string(record.get("weightKg")))
    put(converted, "recorded_at", record.get("recordedAt"))
    put(converted, "time_zone_identifier", record.get("timeZoneIdentifier"))
    put(converted, "notes", record.get("notes"))
    put(converted, "client_mutation_id", record.get("clientMutationId"))
    put(converted, "source_daily_log_entry_id", record.get("sourceDailyLogEntryId"))
    put(converted, "source_chat_message_id", record.get("sourceChatMessageId"))
    return converted


def convert_injection(record: dict[str, Any]) -> dict[str, Any]:
    converted = base_record(record)
    put(converted, "dose_mg", decimal_string(record.get("doseMg")))
    put(converted, "injection_site", record.get("injectionSite"))
    put(converted, "injection_date", record.get("injectionDate"))
    put(converted, "time_zone_identifier", record.get("timeZoneIdentifier"))
    put(converted, "batch_number", record.get("batchNumber"))
    put(converted, "notes", record.get("notes"))
    put(converted, "client_mutation_id", record.get("clientMutationId"))
    put(converted, "source_chat_message_id", record.get("sourceChatMessageId"))
    return converted


def convert_treatment_pause(record: dict[str, Any]) -> dict[str, Any]:
    converted = base_record(record)
    put(converted, "started_at", record.get("startedAt"))
    put(converted, "ended_at", record.get("endedAt"))
    put(converted, "reason", record.get("reason"))
    put(converted, "resumed_on_date", record.get("resumedOnDate"))
    return converted


def convert_daily_log(record: dict[str, Any]) -> dict[str, Any]:
    converted = base_record(record)
    put(converted, "log_date", record.get("logDate"))
    put(converted, "side_effects_json", record.get("sideEffectsJSON"))
    put(converted, "activity_json", record.get("activityJSON"))
    put(converted, "mental_json", record.get("mentalJSON"))
    put(converted, "diet_json", record.get("dietJSON"))
    put(converted, "notes", record.get("notes"))
    return converted


def convert_daily_log_entry(record: dict[str, Any]) -> dict[str, Any]:
    converted = base_record(record)
    put(converted, "log_date", record.get("logDate"))
    put(converted, "recorded_at", record.get("recordedAt"))
    put(converted, "time_zone_identifier", record.get("timeZoneIdentifier"))
    put(converted, "source", record.get("source"))
    put(converted, "raw_text", record.get("entryText"))
    put(converted, "entry_text", record.get("entryText"))
    put(converted, "parsed_draft_json", record.get("parsedDraftJSON"))
    put(converted, "deleted_at", record.get("deletedAt"))
    put(converted, "source_daily_log_id", record.get("sourceDailyLogId"))
    put(converted, "source_chat_message_id", record.get("sourceChatMessageId"))
    put(converted, "client_mutation_id", record.get("clientMutationId"))
    return converted


def convert_export(native: dict[str, Any], source_bytes: bytes) -> dict[str, Any]:
    metadata = native.get("metadata") or {}
    receipts = native.get("receipts") or []
    subject_email = next(
        (receipt.get("sourceEmail") for receipt in receipts if receipt.get("sourceEmail")),
        "unknown",
    )
    source_user_id = next(
        (
            record.get("sourceUserId")
            for collection in ("profiles", "preferences", "weights", "injections", "treatmentPauses", "dailyLogs", "dailyLogEntries")
            for record in native.get(collection, [])
            if record.get("sourceUserId")
        ),
        None,
    )
    app_version = metadata.get("appVersion") or "unknown"
    build_number = metadata.get("buildNumber") or "unknown"

    return {
        "meta": {
            "sourceProduct": "gaurava-ios-native-export",
            "targetProduct": "gaurava-ios",
            "subjectEmail": subject_email,
            "exportedAt": metadata.get("generatedAt"),
            "version": f"native-{app_version}+{build_number}",
            "sha256": hashlib.sha256(source_bytes).hexdigest(),
        },
        "account": {
            "id": source_user_id,
            "email": subject_email,
        },
        "counts": {
            "profiles": len(native.get("profiles", [])),
            "userPreferences": len(native.get("preferences", [])),
            "weightEntries": len(native.get("weights", [])),
            "injections": len(native.get("injections", [])),
            "treatmentPauses": len(native.get("treatmentPauses", [])),
            "dailyLogs": len(native.get("dailyLogs", [])),
            "dailyLogEntries": len(native.get("dailyLogEntries", [])),
        },
        "data": {
            "profiles": [convert_profile(record) for record in native.get("profiles", [])],
            "userPreferences": [convert_preference(record) for record in native.get("preferences", [])],
            "weightEntries": [convert_weight(record) for record in native.get("weights", [])],
            "injections": [convert_injection(record) for record in native.get("injections", [])],
            "treatmentPauses": [convert_treatment_pause(record) for record in native.get("treatmentPauses", [])],
            "dailyLogs": [convert_daily_log(record) for record in native.get("dailyLogs", [])],
            "dailyLogEntries": [convert_daily_log_entry(record) for record in native.get("dailyLogEntries", [])],
            "sideEffects": [],
            "checkIns": [],
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="Native Gaurava export JSON")
    parser.add_argument("output", type=Path, help="Converted seed envelope JSON")
    args = parser.parse_args()

    source_bytes = args.input.read_bytes()
    native = json.loads(source_bytes)
    converted = convert_export(native, source_bytes)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(converted, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    counts = converted["counts"]
    print(
        "Converted "
        f"{args.input} -> {args.output} "
        f"({counts['profiles']} profile, {counts['userPreferences']} preferences, "
        f"{counts['weightEntries']} weights, {counts['injections']} jabs, "
        f"{counts['dailyLogs']} daily logs, {counts['dailyLogEntries']} log entries)"
    )


if __name__ == "__main__":
    main()
