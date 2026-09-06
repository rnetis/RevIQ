import SwiftUI

struct MaintenanceView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: LiveSession

    @State private var showingAdd = false
    @State private var newTitle = ""
    @State private var newIntervalKm = ""
    @State private var newIntervalMonths = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                odometerCard
                itemsList
            }
            .padding(16)
        }
        .background(Theme.bgGradient.ignoresSafeArea())
        .navigationTitle("Maintenance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Theme.neonGreen)
                }
            }
        }
        .sheet(isPresented: $showingAdd) { addSheet }
    }

    private var odometerCard: some View {
        NeonCard(title: "Odometer", icon: "road.lanes", tint: Theme.neonCyan) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(Format.distance(settings.currentOdometerKm, settings.units, decimals: 0)) \(Format.distanceUnit(settings.units))")
                        .font(.hudMono(24, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text(settings.sampleOdoNote)
                        .font(.hud(10.5))
                        .foregroundStyle(Theme.textDim)
                }
                Spacer()
                ScoreRing(score: healthScore, size: 66, lineWidth: 8)
            }
        }
    }

    /// % of items that are not overdue — a simple fleet-health view.
    private var healthScore: Double {
        guard !session.maintenance.isEmpty else { return 100 }
        let fresh = session.maintenance.filter { $0.progress(currentOdoKm: settings.currentOdometerKm) < 0.9 }.count
        return Double(fresh) / Double(session.maintenance.count) * 100
    }

    private var itemsList: some View {
        VStack(spacing: 10) {
            ForEach(session.maintenance.sorted { $0.progress(currentOdoKm: settings.currentOdometerKm) > $1.progress(currentOdoKm: settings.currentOdometerKm) }) { item in
                itemRow(item)
                    .contextMenu {
                        Button(role: .destructive) {
                            session.deleteMaintenance(item)
                        } label: {
                            Label("Delete item", systemImage: "trash")
                        }
                    }
            }
        }
    }

    private func itemRow(_ item: MaintenanceItem) -> some View {
        let progress = item.progress(currentOdoKm: settings.currentOdometerKm)
        let tint: Color = progress >= 1 ? Theme.neonRed : progress >= 0.85 ? Theme.neonAmber : Theme.neonGreen
        let statusText = progress >= 1 ? "OVERDUE" : progress >= 0.85 ? "DUE SOON" : "OK"

        return NeonCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Image(systemName: item.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 9).fill(tint.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.hud(13.5, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(item.dueLabel)
                            .font(.hud(10))
                            .foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                    Text(statusText)
                        .font(.hud(9, weight: .heavy))
                        .kerning(1)
                        .foregroundStyle(tint)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.panelHi)
                        Capsule()
                            .fill(tint)
                            .frame(width: max(5, geo.size.width * CGFloat(min(progress, 1))))
                    }
                }
                .frame(height: 6)

                HStack {
                    Text(lastServiceText(item))
                        .font(.hud(10))
                        .foregroundStyle(Theme.textFaint)
                    Spacer()
                    Button {
                        session.markServiced(item)
                    } label: {
                        Label("Serviced", systemImage: "checkmark")
                            .font(.hud(10.5, weight: .bold))
                            .foregroundStyle(Theme.neonGreen)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().strokeBorder(Theme.neonGreen.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func lastServiceText(_ item: MaintenanceItem) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        var text = "Serviced \(df.string(from: item.lastServiceDate))"
        if item.lastServiceOdoKm > 0 {
            text += " · \(Format.distance(item.lastServiceOdoKm, settings.units, decimals: 0)) \(Format.distanceUnit(settings.units))"
        }
        return text
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("e.g. Serpentine belt", text: $newTitle)
                }
                Section("Interval (optional)") {
                    TextField("Every X km", text: $newIntervalKm)
                        .keyboardType(.numberPad)
                    TextField("Every X months", text: $newIntervalMonths)
                        .keyboardType(.numberPad)
                }
                Section {
                    Button("Add item") {
                        add()
                    }
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("New item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAdd = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func add() {
        session.addMaintenance(title: newTitle.trimmingCharacters(in: .whitespaces),
                               intervalKm: Double(newIntervalKm),
                               intervalMonths: Double(newIntervalMonths))
        newTitle = ""
        newIntervalKm = ""
        newIntervalMonths = ""
        showingAdd = false
    }
}

extension AppSettings {
    var sampleOdoNote: String {
        vehicle.odometerKm > 0
            ? "Synced from the ECU odometer PID or set manually"
            : "Set it manually — updated automatically when the car reports its odometer"
    }
}
