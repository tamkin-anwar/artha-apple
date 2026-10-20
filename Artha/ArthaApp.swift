import SwiftUI

@main
struct ArthaApp: App {
    @State private var month = MonthModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(month)
        }
    }
}

/// The four tabs plus Add, which sits in its own circle beside the tab bar
/// (the search role's slot) and opens a sheet instead of a screen.
struct RootView: View {
    enum Destination: Hashable { case today, activity, plan, wealth, add }

    @State private var selection: Destination = .today
    @State private var isAdding = false

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "gauge.with.dots.needle.33percent", value: .today) {
                TodayView()
            }
            Tab("Activity", systemImage: "list.bullet", value: .activity) {
                ComingNext(title: "Activity", symbol: "list.bullet")
            }
            Tab("Plan", systemImage: "chart.line.uptrend.xyaxis", value: .plan) {
                ComingNext(title: "Plan", symbol: "chart.line.uptrend.xyaxis")
            }
            Tab("Wealth", systemImage: "chart.bar.fill", value: .wealth) {
                ComingNext(title: "Wealth", symbol: "chart.bar.fill")
            }
            Tab("Add", systemImage: "plus", value: .add, role: .search) {
                Color.clear
            }
        }
        .tint(Palette.accent)
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: selection) { previous, current in
            if current == .add {
                selection = previous
                isAdding = true
            }
        }
        .sheet(isPresented: $isAdding) {
            AddSheet()
        }
    }
}

private struct ComingNext: View {
    let title: String
    let symbol: String

    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text("Designed after Today is settled."))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.ground)
    }
}
