import SwiftUI

// MARK: - Palette

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

/// RevIQ dark cockpit HUD palette.
enum Theme {
    static let bg          = Color(hex: 0x0B0F14)
    static let bgElevated  = Color(hex: 0x0E141B)
    static let panel       = Color(hex: 0x121A22)
    static let panelHi     = Color(hex: 0x18232E)
    static let panelStroke = Color(hex: 0x1E2A36)

    static let neonGreen   = Color(hex: 0x22FFB2)
    static let neonCyan    = Color(hex: 0x2FD9FF)
    static let neonAmber   = Color(hex: 0xFFB84D)
    static let neonRed     = Color(hex: 0xFF5C5C)
    static let neonPurple  = Color(hex: 0xB388FF)

    static let textPrimary = Color(hex: 0xEAF6FF)
    static let textDim     = Color(hex: 0x7C93A6)
    static let textFaint   = Color(hex: 0x51677A)

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [neonCyan, neonGreen],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var scoreGradient: LinearGradient {
        LinearGradient(colors: [neonGreen, neonCyan],
                       startPoint: .bottom, endPoint: .top)
    }

    static var warnGradient: LinearGradient {
        LinearGradient(colors: [neonAmber, neonRed],
                       startPoint: .bottomLeading, endPoint: .topTrailing)
    }

    static var bgGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: 0x0C1118), Color(hex: 0x090D12), Color(hex: 0x0B0F14)],
                       startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Typography

extension Font {
    static func hud(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func hudMono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Panel styling

extension View {
    /// Frosted dark card with a hairline neon stroke.
    func hudPanel(cornerRadius: CGFloat = 18, tint: Color = Theme.panelStroke) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(tint.opacity(0.55), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.45), radius: 12, y: 6)
        )
    }

    func neonGlow(_ color: Color, radius: CGFloat = 8) -> some View {
        shadow(color: color.opacity(0.65), radius: radius)
    }
}

// MARK: - Formatting helpers

enum Format {
    static func speed(_ kmh: Double, _ units: UnitsSystem) -> String {
        units == .metric ? String(Int(kmh.rounded())) : String(Int((kmh * 0.621371).rounded()))
    }

    static func speedUnit(_ units: UnitsSystem) -> String {
        units == .metric ? "km/h" : "mph"
    }

    static func distance(_ km: Double, _ units: UnitsSystem, decimals: Int = 1) -> String {
        let v = units == .metric ? km : km * 0.621371
        return String(format: "%.\(decimals)f", v)
    }

    static func distanceUnit(_ units: UnitsSystem) -> String {
        units == .metric ? "km" : "mi"
    }

    static func temp(_ c: Double, _ units: UnitsSystem) -> String {
        units == .metric ? String(Int(c.rounded())) : String(Int((c * 9 / 5 + 32).rounded()))
    }

    static func tempUnit(_ units: UnitsSystem) -> String {
        units == .metric ? "°C" : "°F"
    }

    static func volume(_ liters: Double, _ units: UnitsSystem, decimals: Int = 2) -> String {
        let v = units == .metric ? liters : liters * 0.264172
        return String(format: "%.\(decimals)f", v)
    }

    static func volumeUnit(_ units: UnitsSystem) -> String {
        units == .metric ? "L" : "gal"
    }

    /// 6.8 L/100km  <->  34.6 MPG (US)
    static func consumption(_ l100: Double, _ units: UnitsSystem) -> String {
        if units == .metric {
            return String(format: "%.1f", l100)
        } else {
            guard l100 > 0 else { return "—" }
            return String(format: "%.1f", 235.215 / l100)
        }
    }

    static func consumptionUnit(_ units: UnitsSystem) -> String {
        units == .metric ? "L/100km" : "MPG"
    }

    static func percent(_ v: Double, decimals: Int = 0) -> String {
        String(format: "%.\(decimals)f%%", v)
    }

    static func rpm(_ v: Double) -> String {
        String(format: "%.0f", v)
    }

    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    static func timerValue(_ seconds: Double) -> String {
        String(format: "%.2fs", seconds)
    }

    static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    static func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}
