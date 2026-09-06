import UIKit

/// Renders driving reports as shareable PDFs using UIGraphicsPDFRenderer (no dependencies).
enum PDFExporter {

    private static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
    private static let margin: CGFloat = 46

    // MARK: - Summary report

    static func summaryPDF(trips: [Trip], settings: AppSettings) -> URL? {
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = 0
            y += drawHeader(title: "RevIQ Driving Report",
                            subtitle: "\(trips.count) trips · \(settings.vehicle.displayName)",
                            page: ctx) + 18

            let avgScore = trips.isEmpty ? 0 : trips.reduce(0.0) { $0 + $1.ecoScore } / Double(trips.count)
            let distance = trips.reduce(0.0) { $0 + $1.distanceKm }
            let fuel = trips.reduce(0.0) { $0 + $1.fuelUsedL }
            let idle = trips.isEmpty ? 0 : trips.reduce(0.0) { $0 + $1.idleS } / max(0.001, trips.reduce(0.0) { $0 + $1.durationS }) * 100
            let avgL100: Double? = distance > 0.3 ? fuel / distance * 100 : nil

            // Score ring + key stats
            drawScoreRing(center: CGPoint(x: 120, y: y + 84), radius: 62, score: avgScore)
            let stats: [(String, String)] = [
                ("Distance", "\(Format.distance(distance, settings.units, decimals: 1)) \(Format.distanceUnit(settings.units))"),
                ("Fuel used", "\(Format.volume(fuel, settings.units)) \(Format.volumeUnit(settings.units))"),
                ("Average use", avgL100.map { "\(Format.consumption($0, settings.units)) \(Format.consumptionUnit(settings.units))" } ?? "—"),
                ("Idle share", String(format: "%.0f%%", idle)),
                ("Avg score", String(format: "%.0f / 100", avgScore))
            ]
            var sy = y + 26
            for (label, value) in stats {
                drawText(label.uppercased(), rect: CGRect(x: 240, y: sy, width: 160, height: 16),
                         font: .systemFont(ofSize: 9, weight: .semibold), color: UIColor(hex: 0x51677A))
                drawText(value, rect: CGRect(x: 400, y: sy - 2, width: 170, height: 20),
                         font: .systemFont(ofSize: 13, weight: .bold), color: UIColor(hex: 0x121A22))
                sy += 27
            }
            y += 190

            // Score chart
            y += drawSectionTitle("Score per trip", at: y) + 10
            let values = Array(trips.prefix(14).reversed()).map { $0.ecoScore }
            y += drawBarChart(values: values,
                              labels: trips.prefix(14).reversed().map { Format.dayLabel($0.startedAt) },
                              rect: CGRect(x: margin, y: y, width: pageRect.width - margin * 2, height: 130),
                              maxValue: 100) + 24

            // Trips table
            y += drawSectionTitle("Trip log", at: y) + 10
            for trip in trips.prefix(12) {
                let line = String(format: "%@  ·  %@  ·  %@ %.0f  ·  %@ %@",
                                  Format.dayLabel(trip.startedAt),
                                  trip.mode.title,
                                  "Score",
                                  trip.ecoScore,
                                  Format.distance(trip.distanceKm, settings.units, decimals: 1),
                                  Format.distanceUnit(settings.units))
                drawText(line, rect: CGRect(x: margin, y: y, width: pageRect.width - margin * 2, height: 18),
                         font: .systemFont(ofSize: 11), color: UIColor(hex: 0x24313E))
                y += 19
                if y > pageRect.height - 80 { break }
            }

            // Tips
            let insights = OfflineCoach.weeklyInsights(trips: trips, units: settings.units)
            if y < pageRect.height - 190 {
                y += 16
                y += drawSectionTitle("Coach insights", at: y) + 8
                for insight in insights.prefix(4) {
                    let font = UIFont.systemFont(ofSize: 10.5)
                    let width = pageRect.width - margin * 2 - 14
                    let bounds = (insight as NSString).boundingRect(
                        with: CGSize(width: width, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin],
                        attributes: [.font: font],
                        context: nil)
                    let h = ceil(bounds.height) + 2
                    drawText(insight, rect: CGRect(x: margin + 14, y: y, width: width, height: h),
                             font: font, color: UIColor(hex: 0x24313E))
                    y += h + 7
                    if y > pageRect.height - 60 { break }
                }
            }

            drawFooter(ctx)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RevIQ-Report-\(Int(Date().timeIntervalSince1970)).pdf")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Trip report

    static func tripPDF(_ trip: Trip, settings: AppSettings) -> URL? {
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            var y = drawHeader(title: "Trip Report",
                               subtitle: "\(Format.shortDate(trip.startedAt)) · \(trip.mode.title) · \(trip.vehicleName)",
                               page: ctx) + 16

            drawScoreRing(center: CGPoint(x: 120, y: y + 80), radius: 60, score: trip.ecoScore)

            let avg = trip.avgL100
            let stats: [(String, String)] = [
                ("Duration", Format.duration(trip.durationS)),
                ("Distance", "\(Format.distance(trip.distanceKm, settings.units, decimals: 1)) \(Format.distanceUnit(settings.units))"),
                ("Fuel used", "\(Format.volume(trip.fuelUsedL, settings.units)) \(Format.volumeUnit(settings.units))"),
                ("Avg use", avg.map { "\(Format.consumption($0, settings.units)) \(Format.consumptionUnit(settings.units))" } ?? "—"),
                ("Top speed", "\(Format.speed(trip.maxSpeed, settings.units)) \(Format.speedUnit(settings.units))"),
                ("Idle share", String(format: "%.0f%%", trip.idleShare)),
                ("Harsh accel / brake", "\(trip.harshAccel) / \(trip.harshBrake)"),
                ("Max RPM", "\(Int(trip.maxRPM))")
            ]
            var sy = y + 14
            for (label, value) in stats {
                drawText(label.uppercased(), rect: CGRect(x: 240, y: sy, width: 170, height: 15),
                         font: .systemFont(ofSize: 9, weight: .semibold), color: UIColor(hex: 0x51677A))
                drawText(value, rect: CGRect(x: 404, y: sy - 2, width: 165, height: 18),
                         font: .systemFont(ofSize: 12.5, weight: .bold), color: UIColor(hex: 0x121A22))
                sy += 24
            }
            y += 200

            // Speed profile
            y += drawSectionTitle("Speed profile", at: y) + 8
            let speedValues = trip.samples.map { $0.s }
            y += drawBarChart(values: speedValues,
                              labels: [],
                              rect: CGRect(x: margin, y: y, width: pageRect.width - margin * 2, height: 110),
                              maxValue: max(60, trip.maxSpeed * 1.1)) + 20

            if let summary = trip.aiSummary, !summary.isEmpty {
                y += drawSectionTitle("AI analyst notes", at: y) + 8
                drawText(summary, rect: CGRect(x: margin, y: y, width: pageRect.width - margin * 2, height: 200),
                         font: .systemFont(ofSize: 10.5), color: UIColor(hex: 0x24313E))
            }

            drawFooter(ctx)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RevIQ-Trip-\(Int(Date().timeIntervalSince1970)).pdf")
        do { try data.write(to: url); return url } catch { return nil }
    }

    // MARK: - Drawing helpers

    @discardableResult
    private static func drawHeader(title: String, subtitle: String, page: UIGraphicsPDFRendererContext) -> CGFloat {
        // top band
        let band = UIBezierPath(rect: CGRect(x: 0, y: 0, width: pageRect.width, height: 6))
        UIColor(hex: 0x2FD9FF).setFill()
        band.fill()
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [UIColor(hex: 0x2FD9FF).cgColor, UIColor(hex: 0x22FFB2).cgColor] as CFArray,
                              locations: [0, 1])!
        let bandPath = UIBezierPath(rect: CGRect(x: 0, y: 0, width: pageRect.width, height: 6)).cgPath
        let context = page.cgContext
        context.saveGState()
        context.addPath(bandPath)
        context.clip()
        context.drawLinearGradient(grad, start: .zero, end: CGPoint(x: pageRect.width, y: 0), options: [])
        context.restoreGState()

        drawText("R E V I Q", rect: CGRect(x: margin, y: 34, width: 300, height: 18),
                 font: .systemFont(ofSize: 11, weight: .heavy), color: UIColor(hex: 0x2FD9FF))
        drawText(title, rect: CGRect(x: margin, y: 52, width: pageRect.width - margin * 2, height: 34),
                 font: .systemFont(ofSize: 25, weight: .heavy), color: UIColor(hex: 0x0B0F14))
        drawText(subtitle, rect: CGRect(x: margin, y: 88, width: pageRect.width - margin * 2, height: 18),
                 font: .systemFont(ofSize: 11.5), color: UIColor(hex: 0x51677A))
        return 110
    }

    private static func drawSectionTitle(_ text: String, at y: CGFloat) -> CGFloat {
        drawText(text.uppercased(), rect: CGRect(x: margin, y: y, width: 400, height: 18),
                 font: .systemFont(ofSize: 11, weight: .heavy), color: UIColor(hex: 0x0B0F14))
        let line = UIBezierPath()
        line.move(to: CGPoint(x: margin, y: y + 16))
        line.addLine(to: CGPoint(x: pageRect.width - margin, y: y + 16))
        line.lineWidth = 1
        UIColor(hex: 0xD5E2EC).setStroke()
        line.stroke()
        return 22
    }

    private static func drawText(_ text: String, rect: CGRect, font: UIFont, color: UIColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        text.draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    private static func drawScoreRing(center: CGPoint, radius: CGFloat, score: Double) {
        let track = UIBezierPath(arcCenter: center, radius: radius,
                                 startAngle: .pi * 0.75, endAngle: .pi * 2.25, clockwise: true)
        track.lineWidth = 14
        track.lineCapStyle = .round
        UIColor(hex: 0xE4EDF4).setStroke()
        track.stroke()

        // progress
        let end = .pi * 0.75 + (.pi * 1.5) * min(max(score / 100, 0), 1)
        let progress = UIBezierPath(arcCenter: center, radius: radius,
                                    startAngle: .pi * 0.75, endAngle: end, clockwise: true)
        progress.lineWidth = 14
        progress.lineCapStyle = .round
        let color: UIColor = score >= 80 ? UIColor(hex: 0x16C98D) : score >= 60 ? UIColor(hex: 0x2FD9FF) : UIColor(hex: 0xFF8A4D)
        color.setStroke()
        progress.stroke()

        // text
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 30, weight: .heavy),
            .foregroundColor: UIColor(hex: 0x0B0F14)
        ]
        let str = String(format: "%.0f", score)
        let size = str.size(withAttributes: attrs)
        str.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attrs)
    }

    @discardableResult
    private static func drawBarChart(values: [Double], labels: [String], rect: CGRect, maxValue: Double) -> CGFloat {
        guard !values.isEmpty else { return rect.height }
        let count = values.count
        let gap: CGFloat = count > 10 ? 3 : 6
        let barWidth = (rect.width - CGFloat(count - 1) * gap) / CGFloat(count)
        let maxV = max(maxValue, 0.001)

        // baseline
        let baseline = UIBezierPath()
        baseline.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        baseline.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        UIColor(hex: 0xD5E2EC).setStroke()
        baseline.stroke()

        for (i, v) in values.enumerated() {
            let h = CGFloat(min(max(v / maxV, 0.01), 1)) * rect.height
            let x = rect.minX + CGFloat(i) * (barWidth + gap)
            let barRect = CGRect(x: x, y: rect.maxY - h, width: barWidth, height: h)
            let path = UIBezierPath(roundedRect: barRect, cornerRadius: min(3, barWidth / 2))
            let scoreColor: UIColor
            if maxValue == 100 {
                scoreColor = v >= 80 ? UIColor(hex: 0x16C98D) : v >= 60 ? UIColor(hex: 0x2FD9FF) : UIColor(hex: 0xFF8A4D)
            } else {
                scoreColor = UIColor(hex: 0x2FD9FF)
            }
            scoreColor.setFill()
            path.fill()
        }

        if labels.count == values.count, rect.height > 90 {
            for (i, label) in labels.enumerated() where i % max(1, values.count / 7) == 0 {
                let x = rect.minX + CGFloat(i) * (barWidth + gap)
                drawText(label, rect: CGRect(x: x - 12, y: rect.maxY + 4, width: barWidth + 24, height: 12),
                         font: .systemFont(ofSize: 7.5), color: UIColor(hex: 0x51677A))
            }
        }
        return rect.height + (labels.isEmpty ? 0 : 18)
    }

    private static func drawFooter(_ ctx: UIGraphicsPDFRendererContext) {
        let text = "Generated by RevIQ · \(Format.shortDate(Date())) · For reference only — always drive responsibly"
        drawText(text,
                 rect: CGRect(x: margin, y: pageRect.height - 34, width: pageRect.width - margin * 2, height: 14),
                 font: .systemFont(ofSize: 8.5), color: UIColor(hex: 0x8FA6B8))
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
