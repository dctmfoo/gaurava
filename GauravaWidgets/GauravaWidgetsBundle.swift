import SwiftUI
import WidgetKit

@main
struct GauravaWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // Home Screen + Lock Screen glance.
        CareGlanceWidget()
        // Interactive medium widget (Build 3).
        CareActionsWidget()
        // Control Center / Lock Screen / Action button controls (Build 3).
        OpenLogControl()
        OpenJabsControl()
        OpenWeightControl()
        // Log v1.1: single system capture entry point (route-then-confirm).
        LogSideEffectControl()
        // Injection-day Live Activity (Build 4).
        GauravaInjectionLiveActivity()
    }
}
