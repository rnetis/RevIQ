import Foundation

/// The on-device coach: converts the live OBD stream into human driving tips.
/// Runs fully offline — the cloud LLM is a bonus layer, never a requirement.
final class OfflineCoach {

    private var lastByKey: [String: Date] = [:]
    private var lastGlobal: Date?
    private var coldEngineWarned = false
    private var idleStart: Date?

    func reset() {
        lastByKey = [:]
        lastGlobal = nil
        coldEngineWarned = false
        idleStart = nil
    }

    /// Called on every new speed/rpm sample. Returns at most one tip, throttled.
    func tick(_ sample: Sample,
              previous: Sample?,
              mode: DrivingMode,
              aiTipsEnabled: Bool,
              chattiness: Double) -> CoachTip? {
        guard aiTipsEnabled else { return nil }
        guard let speed = sample.speed, let rpm = sample.rpm else { return nil }

        // Global cooldown scales inversely with chattiness (0.2 → 25 s, 1.0 → 6 s)
        let globalGap = 30 - chattiness * 24
        if let last = lastGlobal, Date().timeIntervalSince(last) < globalGap { return nil }

        // Cooldown per key
        func cooled(_ key: String, _ gap: Double) -> Bool {
            if let last = lastByKey[key], Date().timeIntervalSince(last) < gap { return false }
            return true
        }

        var tip: CoachTip?

        if speed < 2, rpm > 450 {
            // idling
            if idleStart == nil { idleStart = Date() }
            if let start = idleStart, Date().timeIntervalSince(start) > 50,
               cooled("idle", 90) {
                tip = CoachTip(id: "idle", kind: .warning, icon: "hourglass",
                               title: "Long idle detected",
                               message: "You've been idling for a while. If you're staying put, switch off the engine — idling burns about 0.7 L/h for nothing.")
            }
        } else {
            idleStart = nil
        }

        if tip == nil, let prev = previous, let prevSpeed = prev.speed {
            let dt = max(0.2, sample.timestamp.timeIntervalSince(prev.timestamp))
            let accel = (speed - prevSpeed) / dt

            if accel > mode.harshAccelKmHs * 1.15, speed > 10, cooled("accel", 12) {
                tip = CoachTip(id: "accel", kind: mode == .sport ? .info : .warning,
                               icon: "hare.fill",
                               title: mode == .sport ? "Nice launch" : "Easy on the throttle",
                               message: mode == .sport
                                    ? "Strong acceleration — the timers are live. On public roads, progressive throttle is faster anyway (better traction)."
                                    : "Sudden throttle inputs can add 10–15% to trip fuel. Build speed progressively — you'll barely feel the difference in pace.")
            } else if accel < mode.harshBrakeKmHs * 1.1, speed > 25, cooled("brake", 14) {
                tip = CoachTip(id: "brake", kind: .warning, icon: "arrow.down.right",
                               title: "Late braking",
                               message: "Lift off earlier and let the engine brake — coasting in gear uses almost zero fuel and saves your pads.")
            }
        }

        if tip == nil, mode != .sport, rpm > mode.rpmCeiling * 1.25, speed < 45, cooled("rpm", 18) {
            tip = CoachTip(id: "rpm", kind: .info, icon: "gauge.with.needle",
                           title: "Revving high at low speed",
                           message: "Shift up around \(Int(mode.rpmCeiling)) RPM in ECO mode. High revs at low speed is the classic fuel killer.")
        }

        if tip == nil, mode == .eco, speed > 112, cooled("speed", 25) {
            tip = CoachTip(id: "speed", kind: .info, icon: "wind",
                           title: "Aero drag zone",
                           message: "Above 110 km/h drag grows with the square of speed. Cruising at 95–100 typically saves 10–20% on the highway.")
        }

        if tip == nil, let coolant = sample.coolant, coolant < 60, speed > 5, !coldEngineWarned {
            coldEngineWarned = true
            tip = CoachTip(id: "cold", kind: .info, icon: "snowflake",
                           title: "Cold engine",
                           message: "Engine is still warming up (\(Int(coolant))°C). Keep it gentle until ~70°C — a cold engine burns up to 40% more.")
        }

        if tip == nil, let maf = sample.maf, speed > 10, throttleIsCoasting(sample), cooled("coast", 20) {
            _ = maf
            tip = CoachTip(id: "coast", kind: .positive, icon: "leaf.fill",
                           title: "Great coasting",
                           message: "Throttle closed, engine braking — this is free driving. Keep using the car's momentum like this.")
        }

        if let tip {
            lastGlobal = Date()
            lastByKey[tip.id] = Date()
        }
        return tip
    }

    private func throttleIsCoasting(_ s: Sample) -> Bool {
        guard let t = s.throttle else { return false }
        return t < 3
    }

    // MARK: Session insights (offline "weekly report" texts)

    static func weeklyInsights(trips: [Trip], units: UnitsSystem) -> [String] {
        guard !trips.isEmpty else {
            return ["No trips recorded yet. Connect your ELM327 adapter and take a drive — insights appear after your first trip."]
        }
        var out: [String] = []
        let total = trips.count
        let distance = trips.reduce(0.0) { $0 + $1.distanceKm }
        let fuel = trips.reduce(0.0) { $0 + $1.fuelUsedL }
        let avgScore = trips.reduce(0.0) { $0 + $1.ecoScore } / Double(total)
        let idleShare = trips.reduce(0.0) { $0 + $1.idleS } / max(1, trips.reduce(0.0) { $0 + $1.durationS }) * 100

        out.append(String(format: "Across %d trips you drove %@ %@ using %@ %@ of fuel — average score %.0f/100.",
                          total,
                          Format.distance(distance, units, decimals: 1),
                          Format.distanceUnit(units),
                          Format.volume(fuel, units),
                          Format.volumeUnit(units),
                          avgScore))

        let best = trips.max { $0.ecoScore < $1.ecoScore }
        let worst = trips.min { $0.ecoScore < $1.ecoScore }
        if let best, let worst, total >= 2 {
            out.append(String(format: "Best trip scored %.0f (%@). Weakest was %.0f (%@) — check what was different: traffic, cold engine, or mood?",
                              best.ecoScore, Format.shortDate(best.startedAt),
                              worst.ecoScore, Format.shortDate(worst.startedAt)))
        }

        if idleShare > 18 {
            out.append(String(format: "Idling made up %.0f%% of your driving time. Shortening warm-ups and drive-thru waits is your cheapest fuel win.", idleShare))
        } else {
            out.append(String(format: "Idle time is a lean %.0f%% — excellent engine-off discipline.", idleShare))
        }

        let harsh = trips.reduce(0) { $0 + $1.harshAccel + $1.harshBrake }
        if Double(harsh) / Double(max(1, distance)) > 3 {
            out.append("Frequent harsh acceleration/braking events detected. Smoother inputs would lift your score and cut fuel use noticeably.")
        } else {
            out.append("Your inputs are smooth — braking and throttle events per km are low. Keep it up.")
        }
        return out
    }

    static func greeting(mode: DrivingMode) -> String {
        switch mode {
        case .eco:
            return "ECO mode is on. I'll nudge you toward early shifts, gentle throttle and smart coasting."
        case .normal:
            return "NORMAL mode: balanced coaching — save fuel without thinking about it too hard."
        case .sport:
            return "SPORT mode: shift lights armed, timers ready. Drive responsibly."
        }
    }
}
