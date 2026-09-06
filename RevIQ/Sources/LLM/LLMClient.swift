import Foundation

// MARK: - Config

struct LLMConfig: Codable, Equatable {
    var baseURL: String = "https://api.openai.com/v1"
    var apiKey: String = ""
    var model: String = "gpt-4o-mini"
    var temperature: Double = 0.6

    var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var cleanedBaseURL: String {
        var s = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    var endpoint: String {
        let base = cleanedBaseURL
        if base.hasSuffix("/chat/completions") { return base }
        return base + "/chat/completions"
    }
}

enum LLMPreset: String, CaseIterable, Identifiable {
    case openai, groq, openrouter, ollama, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .openai: return "OpenAI"
        case .groq: return "Groq"
        case .openrouter: return "OpenRouter"
        case .ollama: return "Ollama (local)"
        case .custom: return "Custom"
        }
    }

    var baseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .ollama: return "http://localhost:11434/v1"
        case .custom: return ""
        }
    }

    var suggestedModel: String {
        switch self {
        case .openai: return "gpt-4o-mini"
        case .groq: return "llama-3.3-70b-versatile"
        case .openrouter: return "openai/gpt-4o-mini"
        case .ollama: return "llama3.1"
        case .custom: return ""
        }
    }
}

// MARK: - Client

struct ChatTurn: Codable {
    let role: String
    let content: String
}

private struct CompletionRequest: Codable {
    let model: String
    let messages: [ChatTurn]
    let temperature: Double
    let max_tokens: Int
}

private struct CompletionResponse: Codable {
    struct Choice: Codable {
        struct Msg: Codable { let content: String? }
        let message: Msg
    }
    let choices: [Choice]
}

enum LLMError: LocalizedError {
    case notConfigured
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AI is not configured. Add an API key in Garage → AI Copilot."
        case .http(let code, let body):
            let snippet = body.prefix(220)
            return "AI request failed (\(code)): \(snippet)"
        }
    }
}

/// Minimal OpenAI-compatible chat-completions client.
/// Works with OpenAI, Groq, OpenRouter, Together, LM Studio, Ollama, llama.cpp server, etc.
final class LLMClient {

    let config: LLMConfig

    init(config: LLMConfig) {
        self.config = config
    }

    func complete(system: String, user: String, history: [ChatTurn] = [], maxTokens: Int = 700) async throws -> String {
        guard config.isConfigured else { throw LLMError.notConfigured }

        var messages: [ChatTurn] = [ChatTurn(role: "system", content: system)]
        messages.append(contentsOf: history)
        messages.append(ChatTurn(role: "user", content: user))

        let body = CompletionRequest(model: config.model,
                                     messages: messages,
                                     temperature: config.temperature,
                                     max_tokens: maxTokens)

        var request = URLRequest(url: URL(string: config.endpoint)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.http(statusCode, text)
        }
        let decoded = try JSONDecoder().decode(CompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw LLMError.http(statusCode, "Empty response")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Feature-level helpers

    func coachReply(history: [ChatMessage], context: String, question: String) async throws -> String {
        var turns: [ChatTurn] = history.suffix(8).map {
            ChatTurn(role: $0.role == .user ? "user" : "assistant", content: $0.text)
        }
        _ = turns.count
        return try await complete(
            system: Self.coachSystemPrompt + "\n\nCURRENT CAR CONTEXT:\n" + context,
            user: question,
            history: turns,
            maxTokens: 500
        )
    }

    func weeklyReport(context: String) async throws -> String {
        try await complete(
            system: Self.reportSystemPrompt,
            user: "Here is my driving data:\n\n" + context + "\n\nWrite my driving report now.",
            maxTokens: 900
        )
    }

    func diagnose(code: String, title: String, context: String) async throws -> String {
        try await complete(
            system: Self.dtcSystemPrompt,
            user: "Fault code \(code): \(title).\n\nCar context:\n\(context)\n\nExplain this code for my car.",
            maxTokens: 450
        )
    }

    // MARK: Prompts

    static let coachSystemPrompt = """
    You are RevIQ, an in-car driving coach integrated with an OBD-II reader. You speak with the driver \
    through short, punchy messages while they may be driving. Rules:
    - Keep answers under 90 words unless the driver asks for detail.
    - Lead with the actionable advice; add one line of reasoning max.
    - Use the live car context (RPM, speed, throttle, temps, scores) when relevant.
    - Never encourage illegal or unsafe driving. In SPORT mode, remind about road safety when relevant.
    - No emojis, no markdown headers. Plain sentences.
    """

    static let reportSystemPrompt = """
    You are RevIQ, an automotive data analyst. Using the trip JSON/summary provided, write a driving report:
    1) "Scorecard" — 4-6 bullet metrics (score trend, fuel, idle, smoothness).
    2) "What went well" — 2-3 bullets.
    3) "Biggest wins" — 3 concrete, personalized tips with estimated savings.
    4) "Watch-outs" — up to 2 issues.
    Tone: expert mechanic meets performance coach. Max 260 words. Plain text, use simple dashes for bullets.
    """

    static let dtcSystemPrompt = """
    You are RevIQ's diagnostic assistant. Given an OBD-II fault code and car context, explain:
    - What the code means in one sentence.
    - 2-4 most likely causes, most common first.
    - Severity: is it OK to keep driving, drive gently, or fix now?
    - A sensible next step a driver can do.
    Max 140 words. Plain text.
    """
}

// MARK: - Context builders

@MainActor
enum CoachContext {

    static func live(session: LiveSession, settings: AppSettings) -> String {
        let s = session.sample
        var lines: [String] = []
        lines.append("Mode: \(settings.preferredMode.rawValue.uppercased())")
        lines.append("Connection: \(session.phase.label)")
        lines.append("Vehicle: \(settings.vehicle.displayName), \(settings.vehicle.fuelType.title), \(settings.vehicle.engineLiters)L \(settings.vehicle.transmission.title)")
        if let rpm = s.rpm { lines.append("RPM: \(Int(rpm))") }
        if let speed = s.speed { lines.append("Speed: \(Int(speed)) km/h") }
        if let t = s.throttle { lines.append("Throttle: \(Int(t))%") }
        if let c = s.coolant { lines.append("Coolant: \(Int(c))°C") }
        if let f = s.fuelLevel { lines.append("Fuel level: \(Int(f))%") }
        if let v = s.voltage { lines.append("Battery: \(String(format: "%.1f", v))V") }
        if let instant = session.instantL100 {
            lines.append("Instant consumption: \(String(format: "%.1f", instant)) L/100km")
        }
        lines.append("Live eco-score: \(Int(session.ecoScore))/100")
        if session.tripActive {
            let st = session.tripStats
            lines.append("Current trip: \(Format.duration(st.durationS)), \(String(format: "%.1f", st.distanceKm)) km, \(String(format: "%.2f", st.fuelUsedL)) L fuel, \(st.harshAccel + st.harshBrake) harsh events")
        }
        return lines.joined(separator: "\n")
    }

    static func tripsSummary(_ trips: [Trip], settings: AppSettings) -> String {
        guard !trips.isEmpty else { return "No trips recorded yet." }
        var lines: [String] = []
        lines.append("Vehicle: \(settings.vehicle.displayName), \(settings.vehicle.fuelType.title), baseline \(String(format: "%.1f", settings.vehicle.baselineL100)) L/100km")
        let recent = Array(trips.prefix(12))
        for trip in recent {
            var l = "Trip \(Format.dayLabel(trip.startedAt)): mode \(trip.mode.rawValue), "
            l += String(format: "%.1f km, %.0f min", trip.distanceKm, trip.durationS / 60)
            if let l100 = trip.avgL100 { l += String(format: ", %.1f L/100km", l100) }
            l += String(format: ", fuel %.2f L, score %.0f/100, idle %.0f%%, harsh %d+%d",
                        trip.fuelUsedL, trip.ecoScore, trip.idleShare, trip.harshAccel, trip.harshBrake)
            lines.append(l)
        }
        let totalDistance = trips.reduce(0.0) { $0 + $1.distanceKm }
        let totalFuel = trips.reduce(0.0) { $0 + $1.fuelUsedL }
        let avgScore = trips.reduce(0.0) { $0 + $1.ecoScore } / Double(trips.count)
        lines.append(String(format: "TOTALS: %d trips, %.1f km, %.2f L, avg score %.0f", trips.count, totalDistance, totalFuel, avgScore))
        return lines.joined(separator: "\n")
    }
}
