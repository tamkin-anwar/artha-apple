// Renders the app icon (1024x1024, plus Dark and Tinted) from vector
// gradients, so it is never an upscaled bitmap.
// Usage: swiftc -parse-as-library Scripts/RenderIcon.swift -o /tmp/artha-render-icon && /tmp/artha-render-icon Artha/Assets.xcassets
import AppKit
import SwiftUI

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// The orb: a blue sphere with an amber sun rising in its upper left.
struct Orb: View {
    var monochrome = false
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().fill(RadialGradient(stops: [
                    .init(color: Color(hex: 0x5C90DE), location: 0),
                    .init(color: Color(hex: 0x3466C0), location: 0.5),
                    .init(color: Color(hex: 0x1D3B8C), location: 0.82),
                    .init(color: Color(hex: 0x142B68), location: 1),
                ], center: UnitPoint(x: 0.64, y: 0.7), startRadius: 0, endRadius: side * 0.78))
                Circle().fill(RadialGradient(stops: [
                    .init(color: Color(hex: 0xFFF4D8), location: 0),
                    .init(color: Color(hex: 0xFFD27A), location: 0.22),
                    .init(color: Color(hex: 0xF5A524).opacity(0.75), location: 0.5),
                    .init(color: Color(hex: 0xF5A524).opacity(0.12), location: 0.78),
                    .init(color: Color(hex: 0xF5A524).opacity(0), location: 1),
                ], center: UnitPoint(x: 0.34, y: 0.31), startRadius: 0, endRadius: side * 0.52))
                Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05), Color(hex: 0x9FBEFF).opacity(0.35)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: side * 0.008)
            }
            .frame(width: side, height: side)
            .grayscale(monochrome ? 1 : 0)
            .brightness(monochrome ? 0.12 : 0)
        }
    }
}

struct Icon: View {
    enum Style { case standard, dark, tinted }
    let style: Style
    var body: some View {
        ZStack {
            switch style {
            case .standard:
                LinearGradient(colors: [Color(hex: 0x17306A), Color(hex: 0x0A1430)], startPoint: .top, endPoint: .bottom)
            case .dark:
                Color(hex: 0x04060C)
            case .tinted:
                Color.black
            }
            Orb(monochrome: style == .tinted)
                .frame(width: 640, height: 640)
                .shadow(color: .black.opacity(style == .tinted ? 0 : 0.35), radius: 40, y: 24)
        }
        .frame(width: 1024, height: 1024)
    }
}

@main
struct RenderIcon {
    @MainActor static func main() throws {
        let assets = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let folder = assets.appendingPathComponent("AppIcon.appiconset")
        try write(Icon(style: .standard), to: folder.appendingPathComponent("icon-1024.png"))
        try write(Icon(style: .dark), to: folder.appendingPathComponent("icon-1024-dark.png"))
        try write(Icon(style: .tinted), to: folder.appendingPathComponent("icon-1024-tinted.png"))
    }

    @MainActor static func write(_ view: some View, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.isOpaque = true
        guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
    }
}
