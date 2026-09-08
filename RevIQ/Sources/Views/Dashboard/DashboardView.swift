import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: LiveSession

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(spacing: 14) {
                ConnectionBanner()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if case .failed = session.phase { session.showAdapterPicker = true }
                        if case .idle = session.phase { session.showAdapterPicker = true }
                    }

                ModeSegmentPicker(mode: $settings.preferredMode)

                Text(settings.preferredMode.tagline)
                    .font(.hud(11))
                    .foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                gaugeCard

                if let tip = session.currentTip {
                    TipBanner(tip: tip)
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                }

                RPMBarView(rpm: session.sample.rpm ?? 0, mode: settings.preferredMode)
                    .padding(.horizontal, 4)

                statsGrid

                liveCharts

                tripCard

                if settings.preferredMode == .sport || !session.timers.isEmpty {
                    timersCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.bgGradient.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $session.showAdapterPicker) {
            AdapterPickerSheet()
        }
        }
    }

    // MARK: Gauge

    private var gaugeCard: some View {
        ZStack(alignment: .topTrailing) {
            NeonCard(tint: settings.preferredMode.color) {
                SpeedGaugeView(speedKmh: session.sample.speed ?? 0,
                               units: settings.units,
                               mode: settings.preferredMode)
                    .padding(.vertical, 6)
            }
            .padding(.top, 18)

            VStack(spacing: 6) {
                ScoreRing(score: session.ecoScore, size: 82, lineWidth: 9)
                Text("ECO SCORE")
                    .font(.hud(8.5, weight: .heavy))
                    .kerning(1.5)
                    .foregroundStyle(Theme.textDim)
            }
            .padding(.trailing, 10)
            .padding(.top, 4)
        }
    }

    // MARK: Stat tiles

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                  spacing: 10) {
            StatTile(label: "Engine", value: session.sample.rpm.map { Format.rpm($0) } ?? "—",
                     unit: "rpm", icon: "tachometer", tint: Theme.neonCyan)
            StatTile(label: "Throttle", value: session.sample.throttle.map { Format.percent($0) } ?? "—",
                     icon: "drop.circle", tint: Theme.neonGreen)
            StatTile(label: "Instant use", value: session.instantL100.map { Format.consumption($0, settings.units) } ?? "—",
                     unit: session.unitsConsumptionLabel, icon: "fuelpump.fill", tint: Theme.neonAmber)
            StatTile(label: "Idle burn", value: session.litersPerHour.map { String(format: "%.2f", $0) } ?? "—",
                     unit: "L/h", icon: "hourglass", tint: Theme.neonAmber)
            StatTile(label: "Coolant", value: session.sample.coolant.map { Format.temp($0, settings.units) } ?? "—",
                     unit: Format.tempUnit(settings.units), icon: "thermometer.medium", tint: .cyan)
            StatTile(label: "Intake air", value: session.sample.intake.map { Format.temp($0, settings.units) } ?? "—",
                     unit: Format.tempUnit(settings.units), icon: "wind", tint: .teal)
            StatTile(label: "Battery", value: session.sample.voltage.map { String(format: "%.1f", $0) } ?? "—",
                     unit: "V", icon: "bolt.car.fill", tint: Theme.neonGreen)
            StatTile(label: "Fuel level", value: session.sample.fuelLevel.map { Format.percent($0) } ?? "—",
                     icon: "gauge.with.dots.needle.bottom.50percent", tint: Theme.neonCyan)
            StatTile(label: "Odometer", value: settings.vehicle.odometerKm > 0
                        ? Format.distance(settings.vehicle.odometerKm, settings.units, decimals: 0)
                        : "—",
                     unit: Format.distanceUnit(settings.units), icon: "road.lanes", tint: Theme.textDim)
            if settings.preferredMode == .sport {
                StatTile(label: "Est. power", value: session.enginePowerKW.map { String(format: "%.0f", $0 * 1.36) } ?? "—",
                         unit: "hp", icon: "hare.fill", tint: Theme.neonRed)
            }
        }
    }

    // MARK: Live charts

    private var liveCharts: some View {
        VStack(spacing: 10) {
            SparkCard(title: "Speed — last 60s",
                      value: "\(Format.speed(session.sample.speed ?? 0, settings.units)) \(Format.speedUnit(settings.units))",
                      tint: Theme.neonCyan,
                      data: session.speedSeries)
            SparkCard(title: "Engine RPM",
                      value: session.sample.rpm.map { "\(Int($0)) rpm" } ?? "—",
                      tint: Theme.neonAmber,
                      data: session.rpmSeries)
            if !session.fuelSeries.isEmpty {
                SparkCard(title: "Consumption",
                          value: session.instantL100.map { "\(Format.consumption($0, settings.units)) \(Format.consumptionUnit(settings.units))" } ?? "—",
                          tint: Theme.neonGreen,
                          data: session.fuelSeries)
            }
        }
    }

    // MARK: Trip

    private var tripCard: some View {
        NeonCard(title: "Trip recorder", icon: "record.circle", tint: Theme.neonRed) {
            if session.tripActive {
                let st = session.tripStats
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        PulsingDot(color: Theme.neonRed)
                        Text("RECORDING")
                            .font(.hud(10.5, weight: .heavy))
                            .kerning(1.5)
                            .foregroundStyle(Theme.neonRed)
                        Spacer()
                        Text(Format.duration(st.durationS))
                            .font(.hudMono(13, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    HStack(spacing: 10) {
                        miniStat("Distance", "\(Format.distance(st.distanceKm, settings.units))", Format.distanceUnit(settings.units))
                        miniStat("Fuel", "\(Format.volume(st.fuelUsedL, settings.units))", Format.volumeUnit(settings.units))
                        miniStat("Idle", "\(Format.duration(st.idleS))", "")
                    }
                    if let l100 = st.distanceKm > 0.3 ? st.fuelUsedL / st.distanceKm * 100 : nil {
                        HStack {
                            Text("Trip average")
                                .font(.hud(11))
                                .foregroundStyle(Theme.textDim)
                            Spacer()
                            Text("\(Format.consumption(l100, settings.units)) \(Format.consumptionUnit(settings.units))")
                                .font(.hudMono(13, weight: .bold))
                                .foregroundStyle(Theme.neonGreen)
                        }
                    }
                    HUDButton(title: "End & save trip", icon: "stop.fill", tint: Theme.neonRed) {
                        session.endTrip()
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Text("Record a trip to build your analytics, scores and AI reports.")
                        .font(.hud(11.5))
                        .foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HUDButton(title: session.phase.isLive ? "Start trip" : "Connect to start",
                              icon: "play.fill",
                              tint: session.phase.isLive ? Theme.neonGreen : Theme.textFaint,
                              filled: session.phase.isLive) {
                        session.startTrip()
                    }
                    .disabled(!session.phase.isLive)
                }
            }
        }
    }

    private func miniStat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.hudMono(14, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(unit.isEmpty ? label : "\(label) · \(unit)")
                .font(.hud(9.5, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panelHi))
    }

    // MARK: Timers

    private var timersCard: some View {
        NeonCard(title: "Performance timers", icon: "timer", tint: Theme.neonAmber) {
            VStack(spacing: 10) {
                if session.timers.isEmpty {
                    Text("Come to a complete stop with the engine running — launch detection arms automatically. Or arm now.")
                        .font(.hud(11.5))
                        .foregroundStyle(Theme.textDim)
                } else {
                    ForEach(session.timers.prefix(4)) { timer in
                        HStack {
                            Image(systemName: "flag.checkered")
                                .foregroundStyle(Theme.neonAmber)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(timer.label)
                                    .font(.hud(12.5, weight: .bold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(Format.dayLabel(timer.date))
                                    .font(.hud(9.5))
                                    .foregroundStyle(Theme.textFaint)
                            }
                            Spacer()
                            Text(Format.timerValue(timer.seconds))
                                .font(.hudMono(16, weight: .heavy))
                                .foregroundStyle(Theme.neonAmber)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panelHi))
                    }
                }
                HStack(spacing: 10) {
                    HUDButton(title: "Arm launch", icon: "bolt.badge.clock", tint: Theme.neonAmber, filled: !session.perfArmed) {
                        session.armTimer()
                    }
                    HUDButton(title: "Clear", icon: "trash", tint: Theme.textFaint, filled: false) {
                        session.clearTimers()
                    }
                }
            }
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppSettings())
        .environmentObject(LiveSession())
        .preferredColorScheme(.dark)
}
