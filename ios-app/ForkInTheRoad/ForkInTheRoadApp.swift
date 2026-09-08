import SwiftUI
import UIKit

@main
struct ForkInTheRoadApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(RoadTheme.accent)
        }
    }
}

enum RoadTheme {
    static let paper = adaptive(light: 0xF3EDDF, dark: 0x191F1E)
    static let panel = adaptive(light: 0xFFF9ED, dark: 0x252D2B)
    static let ink = adaptive(light: 0x202D29, dark: 0xF3EDDF)
    static let muted = adaptive(light: 0x62685D, dark: 0xB5BDB2)
    static let accent = adaptive(light: 0xAD3D20, dark: 0xF09470)
    static let onAccent = adaptive(light: 0xFFFFFF, dark: 0x192923)
    static let teal = adaptive(light: 0x28655C, dark: 0x87C3B0)
    static let line = adaptive(light: 0xCEC7B6, dark: 0x505B53)
    static let asphalt = Color(red: 0.10, green: 0.16, blue: 0.14)
    static let cream = Color(red: 0.98, green: 0.95, blue: 0.87)
    static let title = Font.system(.largeTitle, design: .serif, weight: .bold)
    static let eyebrow = Font.system(.caption, design: .monospaced, weight: .bold)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

extension View {
    func roadPanel() -> some View {
        self
            .background(RoadTheme.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(RoadTheme.line, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

struct RoadButtonStyle: ButtonStyle {
    var secondary = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .bold))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minWidth: 48, minHeight: 48)
            .foregroundStyle(secondary ? RoadTheme.ink : RoadTheme.onAccent)
            .background(
                secondary ? RoadTheme.panel : RoadTheme.accent,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(secondary ? RoadTheme.line : .clear, lineWidth: 1)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}

struct RoadMark: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                RoundedRectangle(cornerRadius: width * 0.18)
                    .fill(RoadTheme.asphalt)
                Path { path in
                    path.move(to: CGPoint(x: width * 0.5, y: height * 0.85))
                    path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.52))
                    path.addLine(to: CGPoint(x: width * 0.25, y: height * 0.22))
                    path.move(to: CGPoint(x: width * 0.5, y: height * 0.52))
                    path.addLine(to: CGPoint(x: width * 0.75, y: height * 0.22))
                }
                .stroke(RoadTheme.cream, style: StrokeStyle(lineWidth: width * 0.15, lineCap: .square))
                Path { path in
                    path.move(to: CGPoint(x: width * 0.5, y: height * 0.83))
                    path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.52))
                    path.addLine(to: CGPoint(x: width * 0.75, y: height * 0.22))
                }
                .stroke(RoadTheme.asphalt, style: StrokeStyle(lineWidth: width * 0.025, dash: [width * 0.07]))
            }
        }
        .accessibilityHidden(true)
    }
}

struct RoadRule: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 1))
                path.addLine(to: CGPoint(x: geometry.size.width, y: 1))
            }
            .stroke(RoadTheme.line, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}
