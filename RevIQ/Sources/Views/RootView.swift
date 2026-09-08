import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: LiveSession

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dash", systemImage: "gauge.high") }

            CoachView()
                .tabItem { Label("Coach", systemImage: "sparkles") }

            AnalyticsView()
                .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }

            GarageView()
                .tabItem { Label("Garage", systemImage: "wrench.and.screwdriver") }
        }
        .onAppear {
            session.attach(settings: settings)
            UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn && session.phase.isLive
        }
        .onChange(of: session.phase) { phase in
            UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn && phase.isLive
        }
        .onChange(of: settings.keepScreenOn) { keepScreenOn in
            UIApplication.shared.isIdleTimerDisabled = keepScreenOn && session.phase.isLive
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}

// MARK: - Connection banner (shared across tabs)

struct ConnectionBanner: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: LiveSession
    var showActions = true

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
            VStack(alignment: .leading, spacing: 1) {
                Text(session.phase.label)
                    .font(.hud(12.5, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if case .failed = session.phase {
                    Text("Tap to retry or use the demo vehicle")
                        .font(.hud(10.5))
                        .foregroundStyle(Theme.textDim)
                } else {
                    Text(settings.vehicle.displayName)
                        .font(.hud(10.5))
                        .foregroundStyle(Theme.textDim)
                }
            }
            Spacer()
            if showActions, !session.phase.isLive {
                Menu {
                    Button { session.startBLE() } label: {
                        Label("Scan ELM327 BLE", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    Button { session.startDemo() } label: {
                        Label("Start demo vehicle", systemImage: "car.front.waves.up")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.neonCyan)
                }
            } else if session.phase.isLive {
                Button {
                    session.disconnect()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.textFaint)
                }
            }
        }
        .padding(12)
        .hudPanel(cornerRadius: 14)
    }

    private var statusIcon: some View {
        Group {
            switch session.phase {
            case .connected, .demo:
                PulsingDot(color: session.phase == .demo ? Theme.neonPurple : Theme.neonGreen)
            case .scanning, .connecting:
                ProgressView().scaleEffect(0.7).tint(Theme.neonCyan)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.hud(13))
                    .foregroundStyle(Theme.neonRed)
            case .idle:
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.hud(13))
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .frame(width: 24)
    }
}

// MARK: - Adapter picker sheet

struct AdapterPickerSheet: View {
    @EnvironmentObject private var session: LiveSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if session.scanning {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Scanning for ELM327 adapters…")
                            .font(.hud(12))
                            .foregroundStyle(Theme.textDim)
                        Spacer()
                    }
                    .padding()
                }

                if session.foundAdapters.isEmpty && !session.scanning {
                    EmptyState(icon: "antenna.radiowaves.left.and.right.slash",
                               title: "No adapters found",
                               message: "Plug your ELM327 BLE adapter into the OBD-II port and turn the ignition ON, then rescan.")
                } else {
                    List(session.foundAdapters) { adapter in
                        Button {
                            dismiss()
                            session.connectAdapter(adapter)
                        } label: {
                            HStack {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .foregroundStyle(Theme.neonCyan)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(adapter.name)
                                        .font(.hud(14, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    if !adapter.serviceUUIDs.isEmpty {
                                        Text(adapter.serviceUUIDs.joined(separator: " · "))
                                            .font(.hud(10))
                                            .foregroundStyle(Theme.textFaint)
                                    }
                                }
                                Spacer()
                                Text("\(adapter.rssi) dBm")
                                    .font(.hudMono(11))
                                    .foregroundStyle(Theme.textDim)
                            }
                        }
                        .listRowBackground(Theme.panel)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }

                VStack(spacing: 10) {
                    HUDButton(title: session.scanning ? "Scanning…" : "Rescan",
                              icon: "arrow.clockwise",
                              tint: Theme.neonCyan,
                              filled: !session.scanning) {
                        session.startBLE()
                    }
                    HUDButton(title: "Use demo vehicle instead",
                              icon: "car.front.waves.up",
                              tint: Theme.neonPurple,
                              filled: false) {
                        dismiss()
                        session.startDemo()
                    }
                }
                .padding()
            }
            .background(Theme.bg)
            .navigationTitle("ELM327 BLE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
