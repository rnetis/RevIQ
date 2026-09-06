import SwiftUI
import Combine

/// App-wide settings persisted in UserDefaults. Internal units are always metric.
@MainActor
final class AppSettings: ObservableObject {

    @Published var units: UnitsSystem {
        didSet { defaults.set(units.rawValue, forKey: "units") }
    }

    @Published var preferredMode: DrivingMode {
        didSet { defaults.set(preferredMode.rawValue, forKey: "preferredMode") }
    }

    @Published var vehicle: VehicleProfile {
        didSet { saveJSON(vehicle, key: "vehicle") }
    }

    @Published var llm: LLMConfig {
        didSet { saveJSON(llm, key: "llm") }
    }

    @Published var aiTipsEnabled: Bool {
        didSet { defaults.set(aiTipsEnabled, forKey: "aiTipsEnabled") }
    }

    @Published var keepScreenOn: Bool {
        didSet { defaults.set(keepScreenOn, forKey: "keepScreenOn") }
    }

    @Published var coachChattiness: Double {
        didSet { defaults.set(coachChattiness, forKey: "coachChattiness") }
    }

    private let defaults = UserDefaults.standard

    init() {
        units = UnitsSystem(rawValue: defaults.string(forKey: "units") ?? "") ?? .metric
        preferredMode = DrivingMode(rawValue: defaults.string(forKey: "preferredMode") ?? "") ?? .eco
        aiTipsEnabled = defaults.object(forKey: "aiTipsEnabled") as? Bool ?? true
        keepScreenOn = defaults.object(forKey: "keepScreenOn") as? Bool ?? true
        coachChattiness = defaults.object(forKey: "coachChattiness") as? Double ?? 0.6
        vehicle = Self.loadJSON(VehicleProfile.self, key: "vehicle") ?? VehicleProfile()
        llm = Self.loadJSON(LLMConfig.self, key: "llm") ?? LLMConfig()
    }

    /// Current odometer: manual profile value, possibly updated by OBD.
    var currentOdometerKm: Double {
        max(vehicle.odometerKm, 0)
    }

    var isLLMConfigured: Bool {
        llm.isConfigured
    }

    // MARK: JSON helpers

    private func saveJSON<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func loadJSON<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
