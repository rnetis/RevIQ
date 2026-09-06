import SwiftUI

// MARK: - Card container

struct NeonCard<Content: View>: View {
    let title: String?
    let icon: String?
    let tint: Color
    let content: Content

    init(title: String? = nil, icon: String? = nil, tint: Color = Theme.neonCyan,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack(spacing: 7) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.hud(12, weight: .bold))
                            .foregroundStyle(tint)
                    }
                    Text(title)
                        .font(.hud(11.5, weight: .bold))
                        .kerning(1.4)
                        .foregroundStyle(Theme.textDim)
                    Spacer()
                }
                .textCase(.uppercase)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel()
    }
}

// MARK: - Stat tile

struct StatTile: View {
    let label: String
    let value: String
    var unit: String = ""
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: icon)
                    .font(.hud(11, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(value)
                .font(.hudMono(19, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            HStack(spacing: 4) {
                if !unit.isEmpty {
                    Text(unit)
                        .font(.hud(9.5, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(label.uppercased())
                    .font(.hud(9, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(cornerRadius: 14)
    }
}

// MARK: - Score ring

struct ScoreRing: View {
    let score: Double
    var size: CGFloat = 100
    var lineWidth: CGFloat = 11

    private var progress: CGFloat {
        CGFloat(min(max(score / 100, 0), 1))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.panelHi, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(colors: [Theme.neonGreen, Theme.neonCyan, Theme.neonAmber],
                                    center: .center,
                                    startAngle: .degrees(0),
                                    endAngle: .degrees(360)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .neonGlow(Theme.neonCyan, radius: 6)
            VStack(spacing: 0) {
                Text(String(Int(score.rounded())))
                    .font(.hud(size * 0.3, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                Text(score.scoreGrade)
                    .font(.hud(size * 0.16, weight: .bold))
                    .foregroundStyle(Theme.neonGreen)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.4), value: score)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.hud(11.5, weight: .bold))
                .kerning(1.6)
                .foregroundStyle(Theme.textDim)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.hud(11, weight: .semibold))
                    .foregroundStyle(Theme.textFaint)
            }
        }
    }
}

// MARK: - Empty state

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.textFaint)
            Text(title)
                .font(.hud(15, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.hud(12))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

// MARK: - Tip banner

struct TipBanner: View {
    let tip: CoachTip
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tip.icon)
                .font(.hud(14, weight: .bold))
                .foregroundStyle(tip.kind.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(tip.title)
                    .font(.hud(13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                if !compact {
                    Text(tip.message)
                        .font(.hud(11.5))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tip.kind.color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(tip.kind.color.opacity(0.35), lineWidth: 1)
                )
        )
    }
}

// MARK: - Mode picker

struct ModeSegmentPicker: View {
    @Binding var mode: DrivingMode

    var body: some View {
        HStack(spacing: 6) {
            ForEach(DrivingMode.allCases) { m in
                let selected = m == mode
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        mode = m
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: m.icon)
                            .font(.hud(12, weight: .bold))
                        Text(m.title)
                            .font(.hud(12.5, weight: .heavy))
                            .kerning(1)
                    }
                    .foregroundStyle(selected ? Color(hex: 0x081014) : Theme.textDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selected ? AnyShapeStyle(m.color) : AnyShapeStyle(Theme.panelHi))
                            .neonGlow(selected ? m.color : .clear, radius: selected ? 10 : 0)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .hudPanel(cornerRadius: 16)
    }
}

// MARK: - Status dot

struct PulsingDot: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .neonGlow(color, radius: pulse ? 6 : 2)
            .scaleEffect(pulse ? 1.15 : 0.95)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

// MARK: - HUD button

struct HUDButton: View {
    let title: String
    let icon: String
    var tint: Color = Theme.neonCyan
    var filled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                Text(title).font(.hud(13, weight: .bold))
            }
            .foregroundStyle(filled ? Color(hex: 0x081014) : tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(filled ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.12)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(tint.opacity(filled ? 0 : 0.5), lineWidth: 1)
                    )
                    .neonGlow(filled ? tint : .clear, radius: 8)
            )
        }
        .buttonStyle(.plain)
    }
}
