import SwiftUI

/// How Artha uses room it has: iPad, landscape, and any window resized wide
/// on iPadOS. Decided by the width actually available rather than by
/// device, so a narrow iPad window gets the iPhone layout and a wide one
/// gets two columns, and nothing is ever just the phone layout stretched.
enum WideLayout {
    /// At or above this width, screens split into two columns.
    static let twoColumnWidth: CGFloat = 820
    /// Wider than this, content stops growing and centers, so lines and
    /// charts stay readable on a 13-inch screen.
    static let maxContentWidth: CGFloat = 1180
}

/// Two columns side by side when wide, otherwise one column with the
/// leading content first.
struct Columns<Leading: View, Trailing: View>: View {
    let isWide: Bool
    var spacing: CGFloat = 20
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        if isWide {
            HStack(alignment: .top, spacing: spacing) {
                VStack(alignment: .leading, spacing: 0) { leading }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 0) { trailing }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                leading
                trailing
            }
        }
    }
}

extension View {
    /// Keeps `width` up to date with this view's width.
    func readWidth(_ width: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width.wrappedValue = $0 }
    }

    /// No wider than the readable maximum, centered in whatever's left.
    func centeredContent() -> some View {
        frame(maxWidth: WideLayout.maxContentWidth).frame(maxWidth: .infinity)
    }
}
