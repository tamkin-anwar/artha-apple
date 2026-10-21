import AppIntents
import SwiftUI
import WidgetKit

@main
struct ArthaWidgetsBundle: WidgetBundle {
    var body: some Widget {
        GlanceWidget()
        AddPurchaseControl()
    }
}

/// A Control Center, Lock Screen and Action button control that opens
/// straight to adding a purchase: the fastest way in for a cash purchase
/// Apple Pay can't see.
struct AddPurchaseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "AddPurchase") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "artha://add")!)) {
                Label("Add a purchase", systemImage: "plus.circle")
            }
        }
        .displayName("Add a purchase")
        .description("Opens Artha ready to add a purchase.")
    }
}
