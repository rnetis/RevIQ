import SwiftUI

// MARK: - Speedometer

struct SpeedGaugeView: View {
    let speedKmh: Double
    let units: UnitsSystem
    let mode: DrivingMode

    private let maxScale: Double = 240
    private let startAngle: Double = 135
    private let sweep: Double = 270

    private var displaySpeed: Double {
        units == .metric ? speedKmh : speedKmh * 0.621371
    }

    private var fraction: Double {
        min(max(speedKmh / maxScale, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2
            ZStack {
                // Track arc
                Circle()
                    .trim(from: 0, to: sweep / 360)
                    .stroke(Theme.panelHi, style: StrokeStyle(lineWidth: side * 0.045, lineCap: .round))
                    .rotationEffect(.degrees(startAngle))

                // Progress arc
                Circle()
                    .trim(from: 0.0001, to: max(0.0002, sweep / 360 * fraction))
                    .stroke(
                        AngularGradient(colors: [mode.color.opacity(0.9), Theme.neonGreen, Theme.neonAmber, Theme.neonRed],
                                        center: .center,
                                        startAngle: .degrees(startAngle),
                                        endAngle: .degrees(startAngle + sweep)),
                        style: StrokeStyle(lineWidth: side * 0.045, lineCap: .round)
                    )
                    .rotationEffect(.degrees(startAngle))
                    .neonGlow(mode.color, radius: 7)

                // Ticks
                ForEach(0..<27, id: \.self) { i in
                    let isMajor = i % 3 == 0
                    Capsule()
                        .fill(isMajor ? Theme.textDim : Theme.textFaint.opacity(0.5))
                        .frame(width: isMajor ? 2.5 : 1.5,
                               height: isMajor ? side * 0.055 : side * 0.03)
                        .offset(y: -radius + side * 0.035)
                        .rotationEffect(.degrees(startAngle + sweep * Double(i) / 26))
                }

                // Major labels
                ForEach(0..<10, id: \.self) { i in
                    let value = maxScale * Double(i) / 9
                    let angle = (startAngle + sweep * Double(i) / 9) * .pi / 180
                    let r = radius - side * 0.125
                    Text(units == .metric ? String(Int(value)) : String(Int(value * 0.621371)))
                        .font(.hudMono(side * 0.052, weight: .semibold))
                        .foregroundStyle(Theme.textFaint)
                        .position(x: radius + r * cos(angle),
                                  y: radius + r * sin(angle))
                }

                // Needle
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.neonRed)
                    .frame(width: side * 0.022, height: radius - side * 0.09)
                    .offset(y: -(radius - side * 0.09) / 2)
                    .rotationEffect(.degrees(startAngle + sweep * fraction))
                    .neonGlow(Theme.neonRed, radius: 5)
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: fraction)

                Circle()
                    .fill(Theme.panelHi)
                    .frame(width: side * 0.09, height: side * 0.09)
                    .overlay(Circle().strokeBorder(Theme.panelStroke, lineWidth: 1))

                // Digital readout
                VStack(spacing: 0) {
                    Text(String(Int(displaySpeed.rounded())))
                        .font(.hudMono(side * 0.19, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                    Text(Format.speedUnit(units))
                        .font(.hud(side * 0.052, weight: .bold))
                        .kerning(2)
                        .foregroundStyle(mode.color)
                }
                .offset(y: radius * 0.42)
            }
            .frame(width: side, height: side)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - RPM shift-light bar

struct RPMBarView: View {
    let rpm: Double
    let mode: DrivingMode

    private let maxRPM: Double = 6500
    private var segments: Int { 24 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(0..<segments, id: \.self) { i in
                    let threshold = Double(i) / Double(segments)
                    let lit = rpm / maxRPM >= threshold
                    let color: Color = threshold < 0.55
                        ? (mode == .sport ? Theme.neonAmber : Theme.neonGreen)
                        : threshold < 0.8 ? Theme.neonAmber : Theme.neonRed
                    Capsule()
                        .fill(lit ? color : Theme.panelHi)
                        .frame(height: 9)
                        .neonGlow(lit ? color : .clear, radius: lit ? 4 : 0)
                        .animation(.linear(duration: 0.12), value: lit)
                }
            }
            HStack {
                Text(caption)
                    .font(.hud(10, weight: .semibold))
                    .foregroundStyle(Theme.textDim)
                Spacer()
                Text("\(Int(rpm)) RPM")
                    .font(.hudMono(10.5, weight: .bold))
                    .foregroundStyle(mode.color)
            }
        }
    }

    private var caption: String {
        switch mode {
        case .eco: return "Shift ≤ \(Int(mode.rpmCeiling)) rpm for best economy"
        case .normal: return "Shift ≤ \(Int(mode.rpmCeiling)) rpm"
        case .sport: return "Shift lights armed · redline \(Int(maxRPM))"
        }
    }
}

// MARK: - Canvas sparkline

struct Sparkline: View {
    let data: [TimeValue]
    let tint: Color
    var height: CGFloat = 64
    var filled = true

    var body: some View {
        Canvas { context, size in
            guard data.count > 1 else {
                let text = context.resolve(Text("waiting for data…")
                    .font(.hud(10))
                    .foregroundColor(Theme.textFaint))
                context.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2))
                return
            }

            let t0 = data.first!.t
            let t1 = max(data.last!.t, t0 + 1)
            let v0 = min(0, data.map(\.v).min() ?? 0)
            let v1 = max(data.map(\.v).max() ?? 1, v0 + 1)

            func point(_ tv: TimeValue) -> CGPoint {
                CGPoint(x: (tv.t - t0) / (t1 - t0) * size.width,
                        y: size.height - (tv.v - v0) / (v1 - v0) * (size.height - 6) - 3)
            }

            var path = Path()
            path.move(to: point(data[0]))
            for p in data.dropFirst() {
                path.addLine(to: point(p))
            }

            if filled {
                var fill = path
                fill.addLine(to: CGPoint(x: size.width, y: size.height))
                fill.addLine(to: CGPoint(x: 0, y: size.height))
                fill.closeSubpath()
                context.fill(fill, with: .color(tint.opacity(0.12)))
            }

            context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

            // live dot
            let last = point(data.last!)
            context.fill(Path(ellipseIn: CGRect(x: last.x - 2.5, y: last.y - 2.5, width: 5, height: 5)),
                         with: .color(tint))
        }
        .frame(height: height)
    }
}

// MARK: - Live chart card

struct SparkCard: View {
    let title: String
    let value: String
    let tint: Color
    let data: [TimeValue]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.hud(10.5, weight: .bold))
                    .kerning(1.2)
                    .foregroundStyle(Theme.textDim)
                Spacer()
                Text(value)
                    .font(.hudMono(12, weight: .bold))
                    .foregroundStyle(tint)
            }
            Sparkline(data: data, tint: tint, height: 58)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(cornerRadius: 14)
    }
}
