import SwiftUI

// MARK: - Driving modes

enum DrivingMode: String, CaseIterable, Codable, Identifiable {
    case eco, normal, sport
    var id: String { rawValue }

    var title: String {
        switch self {
        case .eco: return "ECO"
        case .normal: return "NORMAL"
        case .sport: return "SPORT"
        }
    }

    var icon: String {
        switch self {
        case .eco: return "leaf.fill"
        case .normal: return "steeringwheel"
        case .sport: return "bolt.fill"
        }
    }

    var color: Color {
        switch self {
        case .eco: return Theme.neonGreen
        case .normal: return Theme.neonCyan
        case .sport: return Theme.neonAmber
        }
    }

    /// RPM above which the engine is considered "wasteful" for this mode.
    var rpmCeiling: Double {
        switch self {
        case .eco: return 2200
        case .normal: return 3000
        case .sport: return 5500
        }
    }

    /// Acceleration (km/h per second) considered harsh for this mode.
    var harshAccelKmHs: Double {
        switch self {
        case .eco: return 6.0
        case .normal: return 9.0
        case .sport: return 13.0
        }
    }

    var harshBrakeKmHs: Double {
        switch self {
        case .eco: return -8.0
        case .normal: return -11.0
        case .sport: return -15.0
        }
    }

    /// Weights: efficiency / smoothness / anticipation / idle / speed discipline
    var scoreWeights: (Double, Double, Double, Double, Double) {
        switch self {
        case .eco: return (0.35, 0.25, 0.20, 0.10, 0.10)
        case .normal: return (0.30, 0.25, 0.20, 0.15, 0.10)
        case .sport: return (0.20, 0.20, 0.20, 0.10, 0.30)
        }
    }

    var tagline: String {
        switch self {
        case .eco: return "Maximum efficiency — gentle inputs, early shifts"
        case .normal: return "Balanced coaching for everyday driving"
        case .sport: return "Performance focus — shift lights & timers"
        }
    }
}

// MARK: - Units

enum UnitsSystem: String, CaseIterable, Codable, Identifiable {
    case metric, imperial
    var id: String { rawValue }
    var title: String { self == .metric ? "Metric (km/h · L/100km)" : "Imperial (mph · MPG)" }
}

enum FuelType: String, CaseIterable, Codable, Identifiable {
    case gasoline, diesel, hybrid, lpg
    var id: String { rawValue }
    var title: String {
        switch self {
        case .gasoline: return "Petrol"
        case .diesel: return "Diesel"
        case .hybrid: return "Hybrid"
        case .lpg: return "LPG"
        }
    }
}

enum Transmission: String, CaseIterable, Codable, Identifiable {
    case automatic, manual
    var id: String { rawValue }
    var title: String { self == .automatic ? "Automatic" : "Manual" }
}

// MARK: - Vehicle profile

struct VehicleProfile: Codable, Equatable {
    var make: String = ""
    var model: String = ""
    var year: Int = 2015
    var fuelType: FuelType = .gasoline
    var engineLiters: Double = 1.6
    var transmission: Transmission = .automatic
    var odometerKm: Double = 0
    /// Typical consumption of this car when driven aggressively — used to compute fuel savings.
    var baselineL100: Double = 9.0

    var displayName: String {
        let parts = [year == 0 ? nil : String(year), make.isEmpty ? nil : make, model.isEmpty ? nil : model].compactMap { $0 }
        return parts.isEmpty ? "Your car" : parts.joined(separator: " ")
    }
}

// MARK: - Live sample

struct Sample: Codable, Equatable {
    var timestamp: Date = Date()
    var rpm: Double?
    var speed: Double?        // km/h
    var throttle: Double?     // %
    var engineLoad: Double?   // %
    var coolant: Double?      // °C
    var intake: Double?       // °C
    var maf: Double?          // g/s
    var map: Double?          // kPa
    var fuelLevel: Double?    // %
    var trimST: Double?       // %
    var trimLT: Double?       // %
    var timing: Double?       // degrees
    /// Distance travelled since diagnostic trouble codes were last cleared (Mode 01 PID 31).
    /// This is not the vehicle odometer.
    var distanceSinceCodesClearedKm: Double?
    var voltage: Double?      // V

    static let empty = Sample()
}

struct TimeValue: Identifiable, Equatable {
    let id = UUID()
    let t: TimeInterval   // seconds since session start
    let v: Double
}

// MARK: - Trips

struct TripSample: Codable, Equatable {
    var t: Double   // seconds since trip start
    var s: Double   // speed km/h
    var r: Double   // rpm
    var th: Double  // throttle %
    var f: Double?  // instant L/100km
}

struct Trip: Identifiable, Codable, Equatable {
    let id: UUID
    var startedAt: Date
    var endedAt: Date
    var mode: DrivingMode
    var vehicleName: String
    var distanceKm: Double
    var durationS: Double
    var idleS: Double
    var fuelUsedL: Double
    var maxSpeed: Double
    var maxRPM: Double
    var harshAccel: Int
    var harshBrake: Int
    var ecoScore: Double
    var samples: [TripSample]
    var aiSummary: String?

    var avgL100: Double? {
        guard distanceKm > 0.3, fuelUsedL > 0 else { return nil }
        return fuelUsedL / distanceKm * 100
    }

    var idleShare: Double {
        guard durationS > 0 else { return 0 }
        return idleS / durationS * 100
    }
}

// MARK: - Performance timers

struct PerfTimerResult: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date
    var label: String      // "0–100 km/h" / "0–60 mph"
    var seconds: Double
    var topSpeed: Double   // km/h at completion
}

// MARK: - Coach

enum CoachTipKind: String, Codable {
    case positive, info, warning, danger

    var color: Color {
        switch self {
        case .positive: return Theme.neonGreen
        case .info: return Theme.neonCyan
        case .warning: return Theme.neonAmber
        case .danger: return Theme.neonRed
        }
    }

    var icon: String {
        switch self {
        case .positive: return "checkmark.seal.fill"
        case .info: return "lightbulb.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "hand.raised.fill"
        }
    }
}

struct CoachTip: Identifiable, Equatable {
    let id: String
    let kind: CoachTipKind
    let icon: String
    let title: String
    let message: String
}

struct ChatMessage: Identifiable, Equatable {
    enum Role: String { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
    let timestamp: Date
    var isError: Bool = false
}

struct DTCCheck: Identifiable, Equatable {
    var id: String { code }
    let code: String
    let title: String
    var known: Bool
}

// MARK: - Maintenance

struct MaintenanceItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var icon: String
    var intervalKm: Double?
    var intervalMonths: Double?
    var lastServiceOdoKm: Double
    var lastServiceDate: Date
    var notes: String?

    /// 0 = fresh, 1 = overdue.
    func progress(currentOdoKm: Double, today: Date = Date()) -> Double {
        var p: [Double] = []
        if let km = intervalKm, km > 0 {
            p.append((currentOdoKm - lastServiceOdoKm) / km)
        }
        if let months = intervalMonths, months > 0 {
            let monthsPassed = today.timeIntervalSince(lastServiceDate) / (30.44 * 24 * 3600)
            p.append(monthsPassed / months)
        }
        guard !p.isEmpty else { return 0 }
        return min(max(p.max() ?? 0, 0), 1.35)
    }

    func isDue(currentOdoKm: Double) -> Bool {
        progress(currentOdoKm: currentOdoKm) >= 0.9
    }

    var dueLabel: String {
        if let km = intervalKm, let months = intervalMonths {
            return "Every \(Int(km)) km / \(Int(months)) mo"
        } else if let km = intervalKm {
            return "Every \(Int(km)) km"
        } else if let months = intervalMonths {
            return "Every \(Int(months)) months"
        }
        return "Custom interval"
    }
}

// MARK: - Connection

enum ConnectPhase: Equatable {
    case idle
    case scanning
    case connecting(String)
    case connected(String)
    case demo
    case failed(String)

    var isLive: Bool {
        if case .connected = self { return true }
        if case .demo = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .idle: return "Not connected"
        case .scanning: return "Scanning for adapters…"
        case .connecting(let n): return "Connecting to \(n)…"
        case .connected(let n): return n
        case .demo: return "Demo vehicle"
        case .failed(let m): return "Failed: \(m)"
        }
    }
}

// MARK: - Live trip stats

struct LiveTripStats: Equatable {
    var startedAt: Date = Date()
    var durationS: Double = 0
    var distanceKm: Double = 0
    var fuelUsedL: Double = 0
    var idleS: Double = 0
    var maxSpeed: Double = 0
    var maxRPM: Double = 0
    var harshAccel: Int = 0
    var harshBrake: Int = 0
}

// MARK: - Score grade

extension Double {
    var scoreGrade: String {
        switch self {
        case 90...: return "A+"
        case 80..<90: return "A"
        case 70..<80: return "B"
        case 60..<70: return "C"
        case 45..<60: return "D"
        default: return "E"
        }
    }
}
