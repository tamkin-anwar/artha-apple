import SwiftUI

/// Today: one number that answers "am I OK?", the month drawn under it,
/// then where the money went, what's coming, and what just happened.
struct TodayView: View {
    @Environment(MonthModel.self) private var month

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TodayHeader()
                if month.hasData {
                    HeroSection()
                        .padding(.horizontal, 20)
                        .padding(.top, 26)
                    PaceChart()
                        .padding(.horizontal, 16)
                        .padding(.top, 22)
                    switch month.status {
                    case .ahead:
                        AheadCard().padding(.horizontal, 16).padding(.top, 24)
                    case .over:
                        OverOptions().padding(.horizontal, 16).padding(.top, 24)
                    case .onPace:
                        EmptyView()
                    }
                    WhereItWent().padding(.top, 30)
                    ComingUp().padding(.top, 30)
                    RecentList()
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                } else {
                    FirstDay()
                }
            }
            .padding(.bottom, 120)
            .animation(.snappy(duration: 0.35), value: month.scenario)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ground)
        .sensoryFeedback(.success, trigger: month.addCount)
        .sensoryFeedback(.impact(weight: .light), trigger: month.scenario)
    }
}

private struct TodayHeader: View {
    @Environment(MonthModel.self) private var month

    var body: some View {
        @Bindable var month = month
        HStack {
            HStack(spacing: 10) {
                OrbMark().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text("MONDAY, OCT 19")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Palette.secondary)
                    Text("Today")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Palette.ink)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Button {} label: {
                    Image(systemName: "sparkle")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44)
                        .background(Palette.surface, in: Circle())
                        .foregroundStyle(Palette.ink)
                }
                .accessibilityLabel("Ask Artha")
                Menu {
                    Picker("Prototype: month", selection: $month.scenario) {
                        ForEach(MonthModel.Scenario.allCases) { scenario in
                            Text(scenario.rawValue).tag(scenario)
                        }
                    }
                } label: {
                    Text("SK")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Palette.raised, in: Circle())
                        .foregroundStyle(Palette.ink)
                }
                .accessibilityLabel("Profile and settings")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 13, weight: .bold))
            .tracking(1)
            .foregroundStyle(Palette.secondary)
    }
}

struct CapsuleButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(prominent ? Palette.inverse : Palette.raised, in: Capsule())
            .foregroundStyle(prominent ? Palette.onInverse : Palette.ink)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

#Preview {
    TodayView().environment(MonthModel())
}
