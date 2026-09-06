import SwiftUI
import Charts

struct AnalyticsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: LiveSession

    @State private var trips: [Trip] = []
    @State private var aiReport: String?
    @State private var generatingReport = false
    @State private var reportError: String?
    @State private var pdfURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    summaryTiles
                    impactCard
                    scoreChart
                    consumptionChart
                    insightsCard
                    aiReportCard
                    tripsSection
                }
                .padding(16)
            }
            .background(Theme.bgGradient.ignoresSafeArea())
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let url = pdfURL {
                        ShareLink(item: url, preview: SharePreview("RevIQ Driving Report")) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .onAppear { reload() }
            .task {
                if let saved = PersistenceManager.shared.loadAIReport(key: weekKey) {
                    if aiReport == nil { aiReport = saved }
                }
            }
        }
    }

    // MARK: Data

    private func reload() {
        trips = PersistenceManager.shared.loadTrips()
        if aiReport == nil {
            aiReport = PersistenceManager.shared.loadAIReport(key: weekKey)
        }
    }

    private var weekKey: String {
        let cal = Calendar.current
        let week = cal.component(.weekOfYear, from: Date())
        let year = cal.component(.yearForWeekOfYear, from: Date())
        return "w\(year)-\(week)"
    }

    private var recentTrips: [Trip] { Array(trips.prefix(30)) }

    private var avgScore: Double {
        trips.isEmpty ? 0 : trips.reduce(0.0) { $0 + $1.ecoScore } / Double(trips.count)
    }

    private var totalDistance: Double { trips.reduce(0.0) { $0 + $1.distanceKm } }
    private var totalFuel: Double { trips.reduce(0.0) { $0 + $1.fuelUsedL } }

    private var savingsL: Double {
        let baselineDistanceFuel = totalDistance / 100 * settings.vehicle.baselineL100
        return max(0, baselineDistanceFuel - totalFuel)
    }

    // MARK: Summary

    private var summaryTiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            StatTile(label: "Trips", value: String(trips.count), icon: "road.lanes", tint: Theme.neonCyan)
            StatTile(label: "Distance", value: Format.distance(totalDistance, settings.units, decimals: 1), unit: Format.distanceUnit(settings.units), icon: "point.topleft.down.curvedto.point.bottomright.up", tint: Theme.neonGreen)
            StatTile(label: "Fuel used", value: Format.volume(totalFuel, settings.units, decimals: 1), unit: Format.volumeUnit(settings.units), icon: "fuelpump.fill", tint: Theme.neonAmber)
            StatTile(label: "Avg score", value: String(Int(avgScore.rounded())), unit: "/ 100", icon: "leaf.fill", tint: Theme.neonGreen)
        }
    }

    private var impactCard: some View {
        NeonCard(title: "Your impact", icon: "leaf.arrow.triangle.circlepath", tint: Theme.neonGreen) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Format.volume(savingsL, settings.units, decimals: 1) + " " + Format.volumeUnit(settings.units))
                        .font(.hud(21, weight: .heavy))
                        .foregroundStyle(Theme.neonGreen)
                    Text("fuel saved vs. your aggressive baseline")
                        .font(.hud(10.5))
                        .foregroundStyle(Theme.textDim)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(String(format: "%.1f kg", FuelMath.co2Kg(liters: savingsL, fuel: settings.vehicle.fuelType)))
                        .font(.hud(21, weight: .heavy))
                        .foregroundStyle(Theme.neonCyan)
                    Text("CO₂ avoided")
                        .font(.hud(10.5))
                        .foregroundStyle(Theme.textDim)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Charts

    private var scoreChart: some View {
        NeonCard(title: "Score per trip", icon: "chart.bar.fill", tint: Theme.neonCyan) {
            if recentTrips.isEmpty {
                EmptyState(icon: "chart.bar", title: "No trips yet", message: "Record a trip on the Dashboard to see trends.")
            } else {
                let points: [ChartPoint] = Array(recentTrips.prefix(14).enumerated().reversed()).map { idx, trip in
                    ChartPoint(id: idx, label: "#\(trips.count - idx)", value: trip.ecoScore,
                               score: trip.ecoScore)
                }
                Chart(points) { point in
                    BarMark(
                        x: .value("Trip", point.label),
                        y: .value("Score", point.value)
                    )
                    .foregroundStyle(point.score >= 80 ? Theme.neonGreen : point.score >= 60 ? Theme.neonCyan : Theme.neonAmber)
                    .cornerRadius(3)
                }
                .chartYScale(domain: 0...100)
                .frame(height: 130)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) {
                        AxisGridLine().foregroundStyle(Theme.panelStroke)
                        AxisValueLabel().foregroundStyle(Theme.textFaint).font(.hud(9))
                    }
                }
                .chartXAxis {
                    AxisMarks {
                        AxisValueLabel().foregroundStyle(Theme.textFaint).font(.hud(9))
                    }
                }
            }
        }
    }

    private var consumptionChart: some View {
        NeonCard(title: "Consumption per trip", icon: "drop.fill", tint: Theme.neonAmber) {
            let points: [ChartPoint] = recentTrips.prefix(14).enumerated().reversed().compactMap { idx, trip in
                guard let l100 = trip.avgL100 else { return nil }
                return ChartPoint(id: 1000 + idx, label: "#\(trips.count - idx)", value: l100, score: 0)
            }
            if points.isEmpty {
                EmptyState(icon: "drop", title: "Not enough data", message: "Consumption is estimated from the MAF sensor on trips longer than ~300 m.")
            } else {
                Chart(points) { point in
                    BarMark(
                        x: .value("Trip", point.label),
                        y: .value("L/100km", point.value)
                    )
                    .foregroundStyle(Theme.neonAmber.opacity(0.85))
                    .cornerRadius(3)
                    RuleMark(y: .value("Baseline", settings.vehicle.baselineL100))
                        .foregroundStyle(Theme.neonRed.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .frame(height: 130)
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine().foregroundStyle(Theme.panelStroke)
                        AxisValueLabel().foregroundStyle(Theme.textFaint).font(.hud(9))
                    }
                }
                .chartXAxis {
                    AxisMarks {
                        AxisValueLabel().foregroundStyle(Theme.textFaint).font(.hud(9))
                    }
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1).fill(Theme.neonRed).frame(width: 14, height: 2)
                    Text("Your baseline \(Format.consumption(settings.vehicle.baselineL100, settings.units)) \(Format.consumptionUnit(settings.units))")
                        .font(.hud(10))
                        .foregroundStyle(Theme.textDim)
                    Spacer()
                }
            }
        }
    }

    // MARK: Insights + AI

    private var insightsCard: some View {
        NeonCard(title: "Coach insights", icon: "lightbulb.fill", tint: Theme.neonGreen) {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(OfflineCoach.weeklyInsights(trips: trips, units: settings.units).enumerated()), id: \.offset) { _, insight in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(Theme.neonGreen).frame(width: 5, height: 5).padding(.top, 5)
                        Text(insight)
                            .font(.hud(11.5))
                            .foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var aiReportCard: some View {
        NeonCard(title: "AI weekly report", icon: "sparkles", tint: Theme.neonPurple) {
            VStack(alignment: .leading, spacing: 10) {
                if let report = aiReport {
                    Text(report)
                        .font(.hud(12))
                        .foregroundStyle(Theme.textPrimary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Let your AI copilot analyze the last trips and write a personalized driving report — what you're doing well and where the fuel is leaking.")
                        .font(.hud(12))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error = reportError {
                    Text("⚠︎ \(error)")
                        .font(.hud(11))
                        .foregroundStyle(Theme.neonRed)
                }

                HUDButton(title: generatingReport ? "Analyzing…" : (aiReport == nil ? "Generate report" : "Regenerate"),
                          icon: "sparkles",
                          tint: Theme.neonPurple,
                          filled: !generatingReport) {
                    generateReport()
                }
                .disabled(generatingReport || trips.isEmpty)
            }
        }
    }

    private func generateReport() {
        guard settings.isLLMConfigured else {
            reportError = "AI is not configured. Add an endpoint + key in Garage → AI Copilot."
            return
        }
        generatingReport = true
        reportError = nil
        let client = LLMClient(config: settings.llm)
        let context = CoachContext.tripsSummary(trips, settings: settings)
        Task {
            do {
                let report = try await client.weeklyReport(context: context)
                aiReport = report
                PersistenceManager.shared.saveAIReport(key: weekKey, text: report)
            } catch {
                reportError = error.localizedDescription
            }
            generatingReport = false
        }
    }

    // MARK: Trips list

    private var tripsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Trip journal", trailing: "\(trips.count) trips")
                Button {
                    exportPDF()
                } label: {
                    Label("PDF", systemImage: "doc.richtext")
                        .font(.hud(11.5, weight: .bold))
                        .foregroundStyle(Theme.neonCyan)
                }
                .disabled(trips.isEmpty)
            }

            if trips.isEmpty {
                NeonCard {
                    EmptyState(icon: "car.rear", title: "Your journal is empty",
                               message: "Connect an ELM327 adapter (or run the demo), then hit “Start trip” on the Dashboard.")
                }
            } else {
                ForEach(trips.prefix(20)) { trip in
                    NavigationLink {
                        TripDetailView(trip: trip) { reload() }
                    } label: {
                        TripRow(trip: trip, units: settings.units)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func exportPDF() {
        if let url = PDFExporter.summaryPDF(trips: trips, settings: settings) {
            pdfURL = url
            reportError = nil
        } else {
            reportError = "PDF generation failed"
        }
    }
}

// MARK: - Trip row

struct TripRow: View {
    let trip: Trip
    let units: UnitsSystem

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text(String(Int(trip.ecoScore)))
                    .font(.hudMono(17, weight: .heavy))
                    .foregroundStyle(trip.ecoScore >= 80 ? Theme.neonGreen : trip.ecoScore >= 60 ? Theme.neonCyan : Theme.neonAmber)
                Text(trip.mode.title)
                    .font(.hud(8, weight: .heavy))
                    .kerning(1)
                    .foregroundStyle(Theme.textFaint)
            }
            .frame(width: 44, height: 44)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panelHi))

            VStack(alignment: .leading, spacing: 3) {
                Text(Format.shortDate(trip.startedAt))
                    .font(.hud(12.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 8) {
                    Label(Format.distance(trip.distanceKm, units) + " " + Format.distanceUnit(units), systemImage: "road.lanes")
                    Label(Format.duration(trip.durationS), systemImage: "clock")
                    if let l100 = trip.avgL100 {
                        Label(Format.consumption(l100, units) + " " + Format.consumptionUnit(units), systemImage: "drop")
                    }
                }
                .font(.hud(10))
                .foregroundStyle(Theme.textDim)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.hud(11, weight: .bold))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(13)
        .hudPanel(cornerRadius: 14)
    }
}

// MARK: - Chart model

struct ChartPoint: Identifiable {
    let id: Int
    let label: String
    let value: Double
    var score: Double = 0
}
