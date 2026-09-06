import SwiftUI
import UIKit

struct GarageView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: LiveSession

    @State private var makeText = ""
    @State private var modelText = ""
    @State private var yearText = ""
    @State private var odoText = ""
    @State private var confirmingClear = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    connectionCard
                    vehicleCard
                    preferencesCard
                    aiCard
                    toolsCard
                    dataCard
                    aboutCard
                }
                .padding(16)
            }
            .background(Theme.bgGradient.ignoresSafeArea())
            .navigationTitle("Garage")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                makeText = settings.vehicle.make
                modelText = settings.vehicle.model
                yearText = settings.vehicle.year == 0 ? "" : String(settings.vehicle.year)
                odoText = settings.vehicle.odometerKm > 0 ? String(Int(settings.vehicle.odometerKm)) : ""
            }
            .confirmationDialog("Erase all trips, maintenance history and AI reports?",
                                isPresented: $confirmingClear,
                                titleVisibility: .visible) {
                Button("Erase everything", role: .destructive) {
                    PersistenceManager.shared.clearAll()
                    session.maintenance = PersistenceManager.shared.loadMaintenance()
                }
            }
        }
    }

    // MARK: Connection

    private var connectionCard: some View {
        NeonCard(title: "OBD-II connection", icon: "antenna.radiowaves.left.and.right", tint: Theme.neonCyan) {
            VStack(spacing: 12) {
                ConnectionBanner(showActions: false)

                HStack(spacing: 10) {
                    HUDButton(title: session.scanning ? "Scanning…" : "Scan BLE",
                              icon: "antenna.radiowaves.left.and.right",
                              tint: Theme.neonCyan,
                              filled: !session.phase.isLive) {
                        session.startBLE()
                    }
                    HUDButton(title: "Demo car",
                              icon: "car.front.waves.up",
                              tint: Theme.neonPurple,
                              filled: false) {
                        session.startDemo()
                    }
                }

                DisclosureGroup {
                    Text("RevIQ auto-detects adapters advertising themselves as OBDII, ELM327, V-Link, Vgate iCar, VEEPEAK, OBDLINK, KONNWEI, ANCEL and similar. If yours doesn't show up, pair it in iOS Settings → Bluetooth first, then rescan. Supported serial services: FFE0, FFF0, 18F0.")
                        .font(.hud(11))
                        .foregroundStyle(Theme.textDim)
                        .padding(.top, 4)
                } label: {
                    Label("Adapter troubleshooting", systemImage: "questionmark.circle")
                        .font(.hud(11.5, weight: .semibold))
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    // MARK: Vehicle

    private var vehicleCard: some View {
        NeonCard(title: "Vehicle profile", icon: "car.fill", tint: Theme.neonGreen) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    hudField("Make", text: $makeText) { settings.vehicle.make = $0 }
                    hudField("Model", text: $modelText) { settings.vehicle.model = $0 }
                    hudField("Year", text: $yearText, keyboard: .numberPad) { raw in
                        settings.vehicle.year = Int(raw) ?? 0
                    }
                }

                Picker("Fuel", selection: $settings.vehicle.fuelType) {
                    ForEach(FuelType.allCases) { fuel in
                        Text(fuel.title).tag(fuel)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Engine")
                        .font(.hud(12))
                        .foregroundStyle(Theme.textDim)
                    Spacer()
                    Text(String(format: "%.1f L", settings.vehicle.engineLiters))
                        .font(.hudMono(12, weight: .bold))
                        .foregroundStyle(Theme.neonGreen)
                }
                Slider(value: $settings.vehicle.engineLiters, in: 0.6...6.5, step: 0.1)
                    .tint(Theme.neonGreen)

                Picker("Transmission", selection: $settings.vehicle.transmission) {
                    ForEach(Transmission.allCases) { t in
                        Text(t.title).tag(t)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    hudField("Odometer (km)", text: $odoText, keyboard: .decimalPad) { raw in
                        settings.vehicle.odometerKm = Double(raw.replacingOccurrences(of: ",", with: ".")) ?? 0
                    }
                }

                HStack {
                    Text("Aggressive baseline")
                        .font(.hud(12))
                        .foregroundStyle(Theme.textDim)
                    Spacer()
                    Text("\(Format.consumption(settings.vehicle.baselineL100, settings.units)) \(Format.consumptionUnit(settings.units))")
                        .font(.hudMono(12, weight: .bold))
                        .foregroundStyle(Theme.neonAmber)
                }
                Slider(value: $settings.vehicle.baselineL100, in: 4...20, step: 0.5)
                    .tint(Theme.neonAmber)
            }
        }
    }

    private func hudField(_ placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default, onChange: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(placeholder.uppercased())
                .font(.hud(8.5, weight: .bold))
                .kerning(1)
                .foregroundStyle(Theme.textFaint)
            TextField(placeholder, text: text)
                .font(.hud(13, weight: .semibold))
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.panelHi))
                .foregroundStyle(Theme.textPrimary)
                .onChange(of: text.wrappedValue) { newValue in
                    onChange(newValue)
                }
        }
    }

    // MARK: Preferences

    private var preferencesCard: some View {
        NeonCard(title: "Preferences", icon: "switch.2", tint: Theme.neonCyan) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Units", selection: $settings.units) {
                    ForEach(UnitsSystem.allCases) { u in
                        Text(u.title).tag(u)
                    }
                }
                .pickerStyle(.menu)

                Picker("Driving mode", selection: $settings.preferredMode) {
                    ForEach(DrivingMode.allCases) { m in
                        Text(m.title).tag(m)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Coach chattiness")
                        .font(.hud(12))
                        .foregroundStyle(Theme.textDim)
                    Spacer()
                    Text(session.chattinessLabel)
                        .font(.hud(11, weight: .bold))
                        .foregroundStyle(Theme.neonCyan)
                }
                Slider(value: $settings.coachChattiness, in: 0.2...1.0, step: 0.1)
                    .tint(Theme.neonCyan)

                Toggle(isOn: $settings.aiTipsEnabled) {
                    Text("Real-time coach tips")
                        .font(.hud(12.5))
                        .foregroundStyle(Theme.textPrimary)
                }
                .tint(Theme.neonGreen)

                Toggle(isOn: $settings.keepScreenOn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep screen awake while connected")
                            .font(.hud(12.5))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Prevents lockscreen during a drive")
                            .font(.hud(10))
                            .foregroundStyle(Theme.textFaint)
                    }
                }
                .tint(Theme.neonGreen)
            }
        }
    }

    // MARK: AI

    private var aiCard: some View {
        NeonCard(title: "AI copilot", icon: "cpu", tint: Theme.neonPurple) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: settings.isLLMConfigured ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(settings.isLLMConfigured ? Theme.neonGreen : Theme.neonAmber)
                    Text(settings.isLLMConfigured
                         ? "Connected to \(settings.llm.model)"
                         : "Not configured — offline coach only")
                        .font(.hud(12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
                NavigationLink {
                    AISettingsView()
                } label: {
                    Label("Configure AI endpoint", systemImage: "key.horizontal")
                        .font(.hud(12.5, weight: .bold))
                        .foregroundStyle(Theme.neonPurple)
                }
            }
        }
    }

    // MARK: Tools

    private var toolsCard: some View {
        VStack(spacing: 10) {
            NavigationLink {
                DTCView()
            } label: {
                toolRow(icon: "stethoscope", title: "Diagnostics (DTC)", subtitle: "Read & explain engine fault codes", tint: Theme.neonRed)
            }
            .buttonStyle(.plain)

            NavigationLink {
                MaintenanceView()
            } label: {
                toolRow(icon: "wrench.and.screwdriver.fill",
                        title: "Maintenance",
                        subtitle: "Service intervals by odometer & time",
                        tint: Theme.neonAmber,
                        badge: dueCount > 0 ? "\(dueCount) due" : nil)
            }
            .buttonStyle(.plain)
        }
    }

    private var dueCount: Int {
        session.maintenance.filter { $0.isDue(currentOdoKm: settings.currentOdometerKm) }.count
    }

    private func toolRow(icon: String, title: String, subtitle: String, tint: Color, badge: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.hud(13.5, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.hud(10.5))
                    .foregroundStyle(Theme.textDim)
            }
            Spacer()
            if let badge {
                Text(badge)
                    .font(.hud(9.5, weight: .heavy))
                    .foregroundStyle(Color(hex: 0x081014))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.neonRed))
            }
            Image(systemName: "chevron.right")
                .font(.hud(11, weight: .bold))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(13)
        .hudPanel(cornerRadius: 14)
    }

    // MARK: Data

    private var dataCard: some View {
        NeonCard(title: "Data", icon: "internaldrive", tint: Theme.textDim) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Stored locally on this device: \(PersistenceManager.shared.storageSizeDescription)")
                    .font(.hud(11.5))
                    .foregroundStyle(Theme.textDim)
                HUDButton(title: "Erase all data", icon: "trash.slash", tint: Theme.neonRed, filled: false) {
                    confirmingClear = true
                }
            }
        }
    }

    private var aboutCard: some View {
        NeonCard(title: "About", icon: "r.square", tint: Theme.neonCyan) {
            VStack(alignment: .leading, spacing: 6) {
                Text("RevIQ 1.0.0 — smart driving companion for ELM327 BLE adapters.")
                    .font(.hud(11.5))
                    .foregroundStyle(Theme.textDim)
                Text("Fuel figures are MAF-based estimates. Coaching advice is educational — always obey traffic laws and keep your eyes on the road.")
                    .font(.hud(11))
                    .foregroundStyle(Theme.textFaint)
            }
        }
    }
}

extension LiveSession {
    var chattinessLabel: String {
        guard let c = settings?.coachChattiness else { return "—" }
        switch c {
        case ..<0.4: return "Calm"
        case ..<0.7: return "Balanced"
        default: return "Chatty"
        }
    }
}
