import XCTest
@testable import Gaurava

/// Efficiency ratchet for first-run onboarding — the automated half of the
/// onboarding "Definition of Done".
///
/// It locks today's per-branch step count so any change that grows or shrinks a
/// branch trips here until the baseline is consciously re-recorded under a named
/// trigger. See `docs/onboarding-definition-of-done.md` (the three criteria and the
/// trigger list) and `docs/plans/2026-06-17-001-feat-onboarding-definition-of-done-plan.md`
/// (R2, R9, U3).
///
/// Counts include the terminal `.close` screen and exclude the shared
/// `welcome → status` preamble (constant across all branches). Adding a brand-new
/// `TreatmentStatus` branch is caught one level earlier: `FirstRunSetupView`'s
/// `branchScreens(for:)` switch is `default`-less, so a new case fails to compile
/// until it is added and baselined here (AE2).
@MainActor
final class OnboardingDefinitionOfDoneTests: XCTestCase {

    /// The committed baseline. Changing onboarding so any of these no longer holds
    /// is permitted ONLY under a trigger from the Definition of Done — update the
    /// count here in the same change and state which trigger applies.
    ///
    /// Re-baselined 2026-06-27 under DoD triggers #3 (new product requirement: a
    /// complete mandatory weight baseline) + #5 (owner-recorded exception) for the
    /// "baseline split + mandatory hard gate" change (docs/onboarding-baseline-split-plan.html
    /// v1.3): each weight decision became its own screen and the active branch gained
    /// a treatment-start screen. These are the CANONICAL counts — `branchStepCount`
    /// reads the static `branchScreens` (which always counts the Apple Health step), so
    /// the lock never depends on the run environment's HealthKit availability. A
    /// HealthKit-less device renders exactly one fewer step per branch (strictly
    /// cheaper); that visible count is covered by the seam test below, not asserted here.
    private static let baseline: [(status: TreatmentStatus, steps: Int)] = [
        (.startingNow, 8),
        (.active, 9),
        (.paused, 6),
        (.unknown, 5),
    ]

    func testBranchStepCountsMatchTheLockedBaseline() {
        for entry in Self.baseline {
            XCTAssertEqual(
                FirstRunSetupView.branchStepCount(for: entry.status),
                entry.steps,
                """
                First-run onboarding step count for \(entry.status) changed \
                (locked baseline: \(entry.steps)). This is the onboarding Efficiency \
                ratchet — a change to the first-run flow is allowed only under a \
                trigger from docs/onboarding-definition-of-done.md. If this change is \
                intentional and cites a trigger, update the baseline above in the same \
                commit; otherwise revert it.
                """
            )
        }
    }

    /// The canonical-vs-visible Apple Health seam (docs/onboarding-baseline-split-plan.html
    /// §5.2): every branch shows the full canonical sequence when HealthKit is
    /// available, and exactly one fewer step — the hidden Apple Health screen — when it
    /// is not. Strictly cheaper, never more. This keeps the conditional Health screen
    /// decoupled from the static ratchet above, so the lock stays deterministic
    /// regardless of the run environment's HealthKit availability.
    func testVisibleStepCountDropsOnlyAppleHealthWhenUnavailable() {
        for status in [TreatmentStatus.startingNow, .active, .paused, .unknown] {
            let canonical = FirstRunSetupView.branchStepCount(for: status)
            XCTAssertEqual(
                FirstRunSetupView.visibleStepCount(for: status, healthAvailable: true),
                canonical,
                "Health-available flow for \(status) must equal the canonical sequence (\(canonical))."
            )
            XCTAssertEqual(
                FirstRunSetupView.visibleStepCount(for: status, healthAvailable: false),
                canonical - 1,
                "Health-unavailable flow for \(status) must drop exactly one step (Apple Health)."
            )
        }
    }
}
