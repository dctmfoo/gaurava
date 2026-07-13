import AppIntents
import SwiftUI
import WidgetKit

// Control Center / Lock Screen / Action button controls (Build 3).
//
// Controls cannot use `Link`, so the open actions use the foreground Open
// intents (which foreground the app and route via the deep-link handoff). Each
// control has a unique `kind`. All are registered in the widget bundle.
//
// NOTE: there is intentionally no privacy-toggle control. Like the in-widget
// toggle, it would run in the extension process and could not reliably refresh
// the separate read-only glance widget (WidgetKit reload budget). Widget privacy
// is owned by the in-app Care > Widget Privacy picker.

struct OpenLogControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.nags.gaurava.control.openLog") {
            ControlWidgetButton(action: OpenLogIntent()) {
                Label(.controlOpenLogLabel, systemImage: "square.and.pencil")
            }
        }
        .displayName(.controlOpenLogDisplayName)
        .description(.controlOpenLogDescription)
    }
}

struct OpenJabsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.nags.gaurava.control.openJabs") {
            ControlWidgetButton(action: OpenJabsIntent()) {
                Label(.controlOpenJabsLabel, systemImage: WidgetSymbol.injection)
            }
        }
        .displayName(.controlOpenJabsDisplayName)
        .description(.controlOpenJabsDescription)
    }
}

struct OpenWeightControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.nags.gaurava.control.openWeight") {
            ControlWidgetButton(action: OpenWeightIntent()) {
                Label(.controlOpenWeightLabel, systemImage: WidgetSymbol.weight)
            }
        }
        .displayName(.controlOpenWeightDisplayName)
        .description(.controlOpenWeightDescription)
    }
}

// Log v1.1: the single system capture entry point. Generic label, no symptom
// names — it opens the app to the Log capture sheet (route-then-confirm). The
// widget never writes; the symptom is recorded when the user taps a chip in-app.
struct LogSideEffectControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.nags.gaurava.control.logSideEffect") {
            ControlWidgetButton(action: LogSideEffectIntent()) {
                Label(.controlLogSideEffectLabel, systemImage: WidgetSymbol.symptom)
            }
        }
        .displayName(.controlLogSideEffectDisplayName)
        .description(.controlLogSideEffectDescription)
    }
}
