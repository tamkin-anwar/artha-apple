import SwiftUI

/// The Artha orb: a blue sphere with an amber sun rising in its upper left.
/// Drawn from gradients at any size, never a bitmap.
struct OrbMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().fill(
                    RadialGradient(stops: [
                        .init(color: Palette.orbLight, location: 0),
                        .init(color: Palette.orbMid, location: 0.5),
                        .init(color: Palette.orbDeep, location: 0.82),
                        .init(color: Palette.orbEdge, location: 1),
                    ], center: UnitPoint(x: 0.64, y: 0.7), startRadius: 0, endRadius: side * 0.78)
                )
                Circle().fill(
                    RadialGradient(stops: [
                        .init(color: Palette.sunCore, location: 0),
                        .init(color: Palette.sunGlow, location: 0.22),
                        .init(color: Palette.sun.opacity(0.75), location: 0.5),
                        .init(color: Palette.sun.opacity(0.12), location: 0.78),
                        .init(color: Palette.sun.opacity(0), location: 1),
                    ], center: UnitPoint(x: 0.34, y: 0.31), startRadius: 0, endRadius: side * 0.52)
                )
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#Preview {
    OrbMark().frame(width: 200, height: 200).padding()
}
