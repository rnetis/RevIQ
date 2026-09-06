import SwiftUI
import UIKit

struct AISettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var model = ""
    @State private var showKey = false
    @State private var testing = false
    @State private var testResult: String?
    @State private var testOK = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                presetsCard
                endpointCard
                testCard
                helpCard
            }
            .padding(16)
        }
        .background(Theme.bgGradient.ignoresSafeArea())
        .navigationTitle("AI Copilot")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            baseURL = settings.llm.baseURL
            apiKey = settings.llm.apiKey
            model = settings.llm.model
        }
    }

    // MARK: Presets

    private var presetsCard: some View {
        NeonCard(title: "Quick presets", icon: "bolt.fill", tint: Theme.neonPurple) {
            VStack(spacing: 8) {
                Text("Tap a provider to fill the endpoint and suggested model — then just paste your API key. Any OpenAI-compatible server works.")
                    .font(.hud(11.5))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(LLMPreset.allCases.filter { $0 != .custom }) { preset in
                        Button {
                            apply(preset)
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: iconFor(preset))
                                    .font(.system(size: 16, weight: .semibold))
                                Text(preset.title)
                                    .font(.hud(11, weight: .bold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panelHi))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func iconFor(_ preset: LLMPreset) -> String {
        switch preset {
        case .openai: return "brain.head.profile"
        case .groq: return "hare.fill"
        case .openrouter: return "arrow.triangle.branch"
        case .ollama: return "desktopcomputer"
        case .custom: return "slider.horizontal.3"
        }
    }

    private func apply(_ preset: LLMPreset) {
        baseURL = preset.baseURL
        model = preset.suggestedModel
        persist()
    }

    // MARK: Endpoint fields

    private var endpointCard: some View {
        NeonCard(title: "Endpoint", icon: "link", tint: Theme.neonCyan) {
            VStack(alignment: .leading, spacing: 12) {
                field("Base URL", text: $baseURL, keyboard: .URL) {
                    settings.llm.baseURL = $0
                    persist()
                }
                field("API key", text: $apiKey, secure: !showKey, keyboard: .asciiCapable) {
                    settings.llm.apiKey = $0
                    persist()
                }
                .overlay(alignment: .trailing) {
                    Button {
                        showKey.toggle()
                    } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.trailing, 10)
                    }
                }
                field("Model", text: $model) {
                    settings.llm.model = $0
                    persist()
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("CREATIVITY")
                            .font(.hud(8.5, weight: .bold))
                            .kerning(1)
                            .foregroundStyle(Theme.textFaint)
                        Spacer()
                        Text(String(format: "%.1f", settings.llm.temperature))
                            .font(.hudMono(11, weight: .bold))
                            .foregroundStyle(Theme.neonCyan)
                    }
                    Slider(value: $settings.llm.temperature, in: 0...1.2, step: 0.1)
                        .tint(Theme.neonCyan)
                        .onChange(of: settings.llm.temperature) { _ in persist() }
                }
            }
        }
    }

    private func field(_ placeholder: String, text: Binding<String>, secure: Bool = false, keyboard: UIKeyboardType = .default, onChange: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(placeholder.uppercased())
                .font(.hud(8.5, weight: .bold))
                .kerning(1)
                .foregroundStyle(Theme.textFaint)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.hudMono(12.5, weight: .medium))
            .keyboardType(keyboard)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.panelHi))
            .foregroundStyle(Theme.textPrimary)
            .onChange(of: text.wrappedValue) { newValue in
                onChange(newValue)
            }
        }
    }

    // MARK: Test

    private var testCard: some View {
        NeonCard(title: "Test connection", icon: "checkmark.icloud", tint: Theme.neonGreen) {
            VStack(alignment: .leading, spacing: 10) {
                if let testResult {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: testOK ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(testOK ? Theme.neonGreen : Theme.neonRed)
                        Text(testResult)
                            .font(.hud(11.5))
                            .foregroundStyle(testOK ? Theme.textDim : Theme.neonRed)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HUDButton(title: testing ? "Testing…" : "Send test message",
                          icon: "paperplane.fill",
                          tint: Theme.neonGreen,
                          filled: !testing) {
                    runTest()
                }
                .disabled(testing)
            }
        }
    }

    private func runTest() {
        persist()
        testing = true
        testResult = nil
        let client = LLMClient(config: settings.llm)
        Task {
            do {
                let reply = try await client.complete(system: "You are a connectivity test.", user: "Reply with exactly: RevIQ AI online", maxTokens: 20)
                testOK = true
                testResult = reply
            } catch {
                testOK = false
                testResult = error.localizedDescription
            }
            testing = false
        }
    }

    // MARK: Help

    private var helpCard: some View {
        NeonCard(title: "How it's used", icon: "lock.shield", tint: Theme.neonAmber) {
            VStack(alignment: .leading, spacing: 7) {
                bullet("Your key stays on this device — it is sent only to the endpoint you configure.")
                bullet("Offline coach tips never require AI; the cloud layer adds chat, weekly reports and DTC explanations.")
                bullet("For a fully local setup, run Ollama and use http://localhost:11434/v1 (or your Mac's LAN IP from the phone).")
                bullet("HTTP endpoints are allowed because local LLM servers don't use HTTPS.")
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Theme.neonAmber).frame(width: 5, height: 5).padding(.top, 5)
            Text(text)
                .font(.hud(11.5))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func persist() {
        settings.llm.baseURL = baseURL
        settings.llm.apiKey = apiKey
        settings.llm.model = model
    }
}
