# Remediation spec backlog

Five Ready specs from the 2026-07-12 module audit, ordered by implementation priority. Each spec is implemented on its declared branch, governed by a GitHub issue filed on this repo when work starts, and its gate is recorded here on completion.

## Milestones 1 → 5

| Order | Spec | Declared branch | Priority rationale | Gate |
|---|---|---|---|---|
| 1 | [Features remediation](SPEC-audit-features.md) | `codex/audit-features` | Fixes the live critical weight-unit defect and establishes shared write/formatting foundations. | — |
| 2 | [Sharing remediation](SPEC-audit-sharing.md) | `codex/audit-sharing` | Closes an active privacy leak, false clinician dose-change reporting, and mixed-locale exports. | — |
| 3 | [Data-layer remediation](SPEC-audit-data-layer.md) | `codex/audit-data-layer` | Adds recoverable persistence, schema migration, import idempotency, calendar correctness, and duplicate reconciliation after write paths stabilize. | — |
| 4 | [Integration remediation](SPEC-audit-integration.md) | `codex/audit-integration` | Fences destructive Release behavior and tightens concurrency/localization/deep-link gates after Features removes existing localization violations. | — |
| 5 | [Surfaces remediation](SPEC-audit-surfaces.md) | `codex/audit-surfaces` | Fixes snapshot compatibility, frozen countdowns, and Live Activity races on top of the stabilized app/data layers. | — |

## Cross-spec coordination notes

- Features D6 cleanup and Integration D3 bare-literal enforcement are a coordinated handoff; Integration's strict catalog sub-gate already exists.
- Surfaces D5's shared-token structural work was completed by the design-system reboot and is satisfied, not reimplemented.
- The write-service consolidation in Features expands the existing `ModelWriteService`; no parallel service is introduced (naming reconciled 2026-07-13).

## Working conventions

- One milestone at a time; branch from a green `main`.
- Record each milestone's gate (test evidence, device handoff result) in the Gate column when it lands.
- Every refactor in these specs is behavior-preserving unless the spec says otherwise.
