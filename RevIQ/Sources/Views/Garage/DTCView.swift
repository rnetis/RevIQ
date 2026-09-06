import SwiftUI

struct DTCView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: LiveSession

    @State private var codes: [DTCCheck] = []
    @State private var scanning = false
    @State private var scanError: String?
    @State private var explanations: [String: String] = [:]
    @State private var explainingCode: String?
    @State private var clearing = false
    @State private var confirmingClear = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                scanCard
                if let scanError {
                    TipBanner(tip: CoachTip(id: "err", kind: .danger, icon: "xmark.octagon.fill",
                                            title: "Scan failed", message: scanError))
                }
                resultsList
                clearCard
            }
            .padding(16)
        }
        .background(Theme.bgGradient.ignoresSafeArea())
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isDemo: Bool {
        session.phase == .demo
    }

    private var scanCard: some View {
        NeonCard(title: "Engine fault codes", icon: "stethoscope", tint: Theme.neonRed) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    PulsingDot(color: session.phase.isLive ? Theme.neonGreen : Theme.neonRed)
                    Text(session.phase.isLive
                         ? (isDemo ? "Demo vehicle — two codes are planted" : "Connected to \(session.phase.label)")
                         : "Connect the car first (Dashboard or Garage)")
                        .font(.hud(12, weight: .semibold))
                        .foregroundStyle(session.phase.isLive ? Theme.textPrimary : Theme.textDim)
                    Spacer()
                }
                Text("Reads Mode $03 stored codes from the ECU and decodes SAE-generic titles. Tap a code for an AI deep-dive of likely causes and severity.")
                    .font(.hud(11.5))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)

                HUDButton(title: scanning ? "Reading codes…" : "Read fault codes",
                          icon: "magnifyingglass",
                          tint: Theme.neonRed,
                          filled: !scanning) {
                    scan()
                }
                .disabled(scanning || !session.phase.isLive)

                if let error = explainingError {
                    Text("⚠︎ \(error)")
                        .font(.hud(11))
                        .foregroundStyle(Theme.neonRed)
                }
            }
        }
    }

    @State private var explainingError: String?

    private var resultsList: some View {
        VStack(spacing: 10) {
            if scanning {
                NeonCard {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Querying ECU (Mode $03)…")
                            .font(.hud(12))
                            .foregroundStyle(Theme.textDim)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else if codes.isEmpty {
                NeonCard {
                    EmptyState(icon: "checkmark.seal.fill", title: "No codes read yet",
                               message: "Tap “Read fault codes” while connected. A clean ECU reports no stored trouble codes.")
                }
            } else {
                NeonCard(title: "\(codes.count) code\(codes.count == 1 ? "" : "s") found",
                         icon: "exclamationmark.triangle.fill",
                         tint: Theme.neonAmber) {
                    VStack(spacing: 10) {
                        ForEach(codes) { code in
                            codeRow(code)
                        }
                    }
                }
            }
        }
    }

    private func codeRow(_ code: DTCCheck) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(code.code)
                    .font(.hudMono(15, weight: .heavy))
                    .foregroundStyle(code.known ? Theme.neonRed : Theme.neonAmber)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.panelHi))
                VStack(alignment: .leading, spacing: 1) {
                    Text(code.title)
                        .font(.hud(12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(code.known ? "SAE generic" : "Extended / manufacturer code")
                        .font(.hud(9.5))
                        .foregroundStyle(Theme.textFaint)
                }
                Spacer()
            }

            if let explanation = explanations[code.code] {
                Text(explanation)
                    .font(.hud(11.5))
                    .foregroundStyle(Theme.textDim)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.neonPurple.opacity(0.08)))
            } else {
                Button {
                    explain(code)
                } label: {
                    HStack(spacing: 6) {
                        if explainingCode == code.code {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(explainingCode == code.code ? "Asking AI…" : "AI diagnosis")
                            .font(.hud(11.5, weight: .bold))
                    }
                    .foregroundStyle(Theme.neonPurple)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.neonPurple.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .disabled(explainingCode != nil)
            }
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panelHi))
    }

    private var clearCard: some View {
        NeonCard(title: "Maintenance mode", icon: "windshield.front.and.wiper", tint: Theme.textDim) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Clearing codes (Mode $04) erases stored codes and resets inspection readiness. Only do this after fixing the underlying issue.")
                    .font(.hud(11.5))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                HUDButton(title: clearing ? "Clearing…" : "Clear fault codes",
                          icon: "eraser.fill",
                          tint: Theme.neonAmber,
                          filled: false) {
                    confirmingClear = true
                }
                .disabled(clearing || !session.phase.isLive || codes.isEmpty)
            }
        }
        .confirmationDialog("Clear all fault codes from the ECU?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear codes", role: .destructive) { clearCodes() }
        }
    }

    // MARK: Actions

    private func scan() {
        scanning = true
        scanError = nil
        Task {
            let result = await session.readDTCs()
            codes = result
            if result.isEmpty && !session.phase.isLive {
                scanError = "Not connected to an adapter."
            }
            scanning = false
        }
    }

    private func explain(_ code: DTCCheck) {
        guard settings.isLLMConfigured else {
            explainingError = "AI is not configured — add a key in Garage → AI Copilot. Meaning: \(code.title)."
            return
        }
        explainingError = nil
        explainingCode = code.code
        let client = LLMClient(config: settings.llm)
        let context = CoachContext.live(session: session, settings: settings)
        Task {
            do {
                let reply = try await client.diagnose(code: code.code, title: code.title, context: context)
                explanations[code.code] = reply
            } catch {
                explainingError = error.localizedDescription
            }
            explainingCode = nil
        }
    }

    private func clearCodes() {
        clearing = true
        Task {
            let ok = await session.clearDTCs()
            if ok {
                codes = []
            } else {
                scanError = "ECU refused or the command timed out. Some cars block clearing while the engine runs."
            }
            clearing = false
        }
    }
}
