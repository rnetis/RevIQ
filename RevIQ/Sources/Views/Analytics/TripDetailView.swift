import SwiftUI
import Charts

struct TripDetailView: View {
    @EnvironmentObject private var settings: AppSettings
    let trip: Trip
    var onChanged: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var aiNotes: String
    @State private var generating = false
    @State private var error: String?
    @State private var pdfURL: URL?
    @State private var confirmingDelete = false

    init(trip: Trip, onChanged: @escaping () -> Void = {}) {
        self.trip = trip
        self.onChanged = onChanged
        _aiNotes = State(initialValue: trip.aiSummary ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerCard
                statsGrid
                speedChart
                rpmChart
                throttleChart
                aiCard
                actionsRow
            }
            .padding(16)
        }
        .background(Theme.bgGradient.ignoresSafeArea())
        .navigationTitle("Trip detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let url = pdfURL {
                    ShareLink(item: url, preview: SharePreview("RevIQ Trip Report"))
                }
            }
        }
        .confirmationDialog("Delete this trip?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                PersistenceManager.shared.deleteTrip(id: trip.id)
                onChanged()
                dismiss()
            }
        }
    }

    // MARK: Sections

    private var headerCard: some View {
        NeonCard {
            HStack(spacing: 14) {
                ScoreRing(score: trip.ecoScore, size: 84, lineWidth: 9)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Format.shortDate(trip.startedAt))
                        .font(.hud(13, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Label("\(trip.mode.title) · \(trip.vehicleName)", systemImage: trip.mode.icon)
                        .font(.hud(11))
                        .foregroundStyle(trip.mode.color)
                    Text("\(Format.duration(trip.durationS)) · \(Format.distance(trip.distanceKm, settings.units)) \(Format.distanceUnit(settings.units))")
                        .font(.hud(11))
                        .foregroundStyle(Theme.textDim)
                }
                Spacer()
            }
        }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            StatTile(label: "Fuel used", value: Format.volume(trip.fuelUsedL, settings.units), unit: Format.volumeUnit(settings.units), icon: "fuelpump.fill", tint: Theme.neonAmber)
            StatTile(label: "Avg use", value: trip.avgL100.map { Format.consumption($0, settings.units) } ?? "—", unit: trip.avgL100 == nil ? "" : Format.consumptionUnit(settings.units), icon: "drop.fill", tint: Theme.neonGreen)
            StatTile(label: "Top speed", value: Format.speed(trip.maxSpeed, settings.units), unit: Format.speedUnit(settings.units), icon: "speedometer", tint: Theme.neonRed)
            StatTile(label: "Max RPM", value: "\(Int(trip.maxRPM))", unit: "rpm", icon: "tachometer", tint: Theme.neonCyan)
            StatTile(label: "Idle time", value: Format.duration(trip.idleS), unit: String(format: "%.0f%%", trip.idleShare), icon: "hourglass", tint: Theme.neonPurple)
            StatTile(label: "Harsh +/−", value: "\(trip.harshAccel)/\(trip.harshBrake)", unit: "events", icon: "waveform.path.ecg.rectangle", tint: Theme.neonRed)
        }
    }

    private var speedChart: some View {
        NeonCard(title: "Speed", icon: "speedometer", tint: Theme.neonCyan) {
            lineChart(values: trip.samples.map { ($0.t, $0.s) }, tint: Theme.neonCyan, unit: "km/h")
        }
    }

    private var rpmChart: some View {
        NeonCard(title: "Engine RPM", icon: "tachometer", tint: Theme.neonAmber) {
            lineChart(values: trip.samples.map { ($0.t, $0.r) }, tint: Theme.neonAmber, unit: "rpm")
        }
    }

    private var throttleChart: some View {
        NeonCard(title: "Throttle", icon: "drop.circle", tint: Theme.neonGreen) {
            lineChart(values: trip.samples.map { ($0.t, $0.th) }, tint: Theme.neonGreen, unit: "%", maxValue: 100)
        }
    }

    private func lineChart(values: [(Double, Double)], tint: Color, unit: String, maxValue: Double? = nil) -> some View {
        Group {
            if values.count < 2 {
                Text("Not enough samples recorded")
                    .font(.hud(11))
                    .foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                let points = values.enumerated().map { idx, pair in
                    ChartPoint(id: idx, label: "", value: pair.1)
                }
                let top = maxValue ?? max(values.map { $0.1 }.max() ?? 1, 1) * 1.08
                Chart(points) { point in
                    AreaMark(
                        x: .value("Index", point.id),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.03)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .interpolationMethod(.catmullRom)
                    LineMark(
                        x: .value("Index", point.id),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(tint)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round))
                }
                .chartYScale(domain: 0...top)
                .frame(height: 110)
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine().foregroundStyle(Theme.panelStroke)
                        AxisValueLabel().foregroundStyle(Theme.textFaint).font(.hud(9))
                    }
                }
                .chartXAxis(.hidden)
                Text("time → · \(unit)")
                    .font(.hud(9))
                    .foregroundStyle(Theme.textFaint)
            }
        }
    }

    private var aiCard: some View {
        NeonCard(title: "AI analyst notes", icon: "sparkles", tint: Theme.neonPurple) {
            VStack(alignment: .leading, spacing: 10) {
                if !aiNotes.isEmpty {
                    Text(aiNotes)
                        .font(.hud(12))
                        .foregroundStyle(Theme.textPrimary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Ask the AI to review this trip: pacing, gear discipline, idle time and where the fuel went.")
                        .font(.hud(12))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error {
                    Text("⚠︎ \(error)")
                        .font(.hud(11))
                        .foregroundStyle(Theme.neonRed)
                }
                HUDButton(title: generating ? "Analyzing…" : (aiNotes.isEmpty ? "Analyze trip" : "Re-analyze"),
                          icon: "sparkles",
                          tint: Theme.neonPurple,
                          filled: !generating) {
                    generateNotes()
                }
                .disabled(generating)
            }
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 10) {
            HUDButton(title: "Export PDF", icon: "doc.richtext", tint: Theme.neonCyan, filled: false) {
                pdfURL = PDFExporter.tripPDF(trip, settings: settings)
            }
            HUDButton(title: "Delete trip", icon: "trash", tint: Theme.neonRed, filled: false) {
                confirmingDelete = true
            }
        }
    }

    private func generateNotes() {
        guard settings.isLLMConfigured else {
            error = "AI is not configured. Add an endpoint + key in Garage → AI Copilot."
            return
        }
        generating = true
        error = nil
        let client = LLMClient(config: settings.llm)
        let context = CoachContext.tripsSummary([trip], settings: settings)
        Task {
            do {
                let notes = try await client.weeklyReport(context: context)
                aiNotes = notes
                var updated = trip
                updated.aiSummary = notes
                PersistenceManager.shared.updateTrip(updated)
                onChanged()
            } catch {
                self.error = error.localizedDescription
            }
            generating = false
        }
    }
}
