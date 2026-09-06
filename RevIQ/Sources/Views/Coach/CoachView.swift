import SwiftUI

struct CoachView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: LiveSession

    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    headerCard

                    if !settings.isLLMConfigured {
                        setupCard
                    }

                    if !session.tipLog.isEmpty {
                        NeonCard(title: "Live tips this session", icon: "bubble.left.and.bubble.right", tint: Theme.neonGreen) {
                            VStack(spacing: 8) {
                                ForEach(session.tipLog) { tip in
                                    TipBanner(tip: tip, compact: true)
                                }
                            }
                        }
                    }

                    chatSection
                }
                .padding(16)
                .padding(.bottom, 8)
            }

            inputBar
            }
        }
        .background(Theme.bgGradient.ignoresSafeArea())
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header

    private var headerCard: some View {
        NeonCard(title: OfflineCoach.greeting(mode: settings.preferredMode), icon: settings.preferredMode.icon, tint: settings.preferredMode.color) {
            HStack(spacing: 14) {
                ScoreRing(score: session.ecoScore, size: 74, lineWidth: 8)
                VStack(alignment: .leading, spacing: 5) {
                    scoreRow("Efficiency", session.scoreComponents.efficiency, Theme.neonGreen)
                    scoreRow("Smoothness", session.scoreComponents.smoothness, Theme.neonCyan)
                    scoreRow("Anticipation", session.scoreComponents.anticipation, Theme.neonAmber)
                    scoreRow("Idle discipline", session.scoreComponents.idle, Theme.neonPurple)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func scoreRow(_ label: String, _ value: Double, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.hud(10.5, weight: .semibold))
                .foregroundStyle(Theme.textDim)
                .frame(width: 92, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.panelHi)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(4, geo.size.width * CGFloat(value / 100)))
                        .neonGlow(tint, radius: 3)
                }
            }
            .frame(height: 5)
            Text(String(Int(value)))
                .font(.hudMono(11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 26, alignment: .trailing)
        }
    }

    private var setupCard: some View {
        NeonCard(title: "Unlock the AI copilot", icon: "cpu", tint: Theme.neonPurple) {
            VStack(alignment: .leading, spacing: 8) {
                Text("The offline coach is active right now. Connect any OpenAI-compatible model (OpenAI, Groq, OpenRouter, local Ollama…) to get a conversational copilot and written weekly reports.")
                    .font(.hud(12))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                NavigationLink {
                    AISettingsView()
                } label: {
                    Label("Configure in Garage → AI Copilot", systemImage: "key.fill")
                        .font(.hud(12.5, weight: .bold))
                        .foregroundStyle(Theme.neonPurple)
                }
            }
        }
    }

    // MARK: Chat

    private var chatSection: some View {
        VStack(spacing: 10) {
            if messages.isEmpty {
                EmptyState(icon: "bubble.left.and.text.bubble.right",
                           title: "Ask your copilot anything",
                           message: "“Why was my score lower today?” · “How's my fuel use this week?” · “What does P0171 mean?”")
            } else {
                ForEach(messages) { message in
                    ChatBubble(message: message)
                }
                if sending {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("RevIQ AI is thinking…")
                            .font(.hud(11))
                            .foregroundStyle(Theme.textDim)
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                }
            }
        }
        .id("chatBottom")
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(session.phase.isLive ? "Ask about your driving…" : "Connect the car for smarter answers…",
                      text: $input, axis: .vertical)
                .font(.hud(13))
                .lineLimit(1...3)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
                .foregroundStyle(Theme.textPrimary)
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: sending ? "hourglass" : "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(canSend ? Theme.neonCyan : Theme.textFaint)
                    .neonGlow(canSend ? Theme.neonCyan : .clear, radius: 6)
            }
            .disabled(!canSend)

            if !messages.isEmpty {
                Button {
                    messages.removeAll()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textFaint)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending
    }

    private func send() {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !sending else { return }
        input = ""

        if !settings.isLLMConfigured {
            messages.append(ChatMessage(role: .user, text: question, timestamp: Date()))
            messages.append(ChatMessage(role: .assistant,
                                        text: "I need an AI endpoint to chat. Open Garage → AI Copilot and paste an OpenAI-compatible URL + API key. Meanwhile, my offline tips keep working — they're already on your Dashboard.",
                                        timestamp: Date(),
                                        isError: true))
            return
        }

        messages.append(ChatMessage(role: .user, text: question, timestamp: Date()))
        sending = true

        let client = LLMClient(config: settings.llm)
        let context = CoachContext.live(session: session, settings: settings)
        let history = messages

        Task {
            do {
                let reply = try await client.coachReply(history: history, context: context, question: question)
                messages.append(ChatMessage(role: .assistant, text: reply, timestamp: Date()))
            } catch {
                messages.append(ChatMessage(role: .assistant,
                                            text: "⚠︎ \(error.localizedDescription)",
                                            timestamp: Date(),
                                            isError: true))
            }
            sending = false
        }
    }
}

// MARK: - Bubble

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 44) }
            VStack(alignment: .leading, spacing: 4) {
                Text(message.text)
                    .font(.hud(12.5))
                    .foregroundStyle(message.isError ? Theme.neonRed : Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.hud(9))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(message.role == .user ? Theme.neonCyan.opacity(0.14) : Theme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(message.isError ? Theme.neonRed.opacity(0.4) : Theme.panelStroke, lineWidth: 1)
                    )
            )
            if message.role == .assistant { Spacer(minLength: 44) }
        }
    }
}
