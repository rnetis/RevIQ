import Foundation

/// Computes the live eco-score (0–100) from the stream of OBD samples.
struct ScoreComponents: Equatable {
    var efficiency: Double = 100
    var smoothness: Double = 100
    var anticipation: Double = 100
    var idle: Double = 100
    var speedDiscipline: Double = 100

    var all: [Double] { [efficiency, smoothness, anticipation, idle, speedDiscipline] }
}

struct ScoringEngine {

    private(set) var components = ScoreComponents()
    private(set) var overall: Double = 100

    private(set) var harshAccelCount = 0
    private(set) var harshBrakeCount = 0

    // accumulators
    private var lastTime: Date?
    private var lastSpeed: Double?
    private var lastAccel: Double?
    private var effEMA: Double = 100
    private var accelPenalty: Double = 0
    private var brakeEvents: Double = 0
    private var totalSeconds: Double = 0.0001
    private var idleSeconds: Double = 0
    private var highRPMSecs: Double = 0
    private var fastSpeedSecs: Double = 0
    private var distanceKm: Double = 0
    private var fuelGrams: Double = 0

    mutating func reset() {
        self = ScoringEngine()
    }

    /// Ingests a new sample; returns updated components + overall score.
    mutating func ingest(_ sample: Sample, mode: DrivingMode, fuelType: FuelType) -> (components: ScoreComponents, overall: Double) {
        let now = sample.timestamp
        defer { lastTime = now; lastSpeed = sample.speed }

        guard let speed = sample.speed, let rpm = sample.rpm else { return (components, overall) }
        var dt: Double = 0
        if let last = lastTime { dt = now.timeIntervalSince(last) }
        guard dt > 0.05, dt < 5 else { return (components, overall) }

        totalSeconds += dt

        // Distance & fuel integration
        distanceKm += speed * dt / 3600
        if let maf = sample.maf {
            fuelGrams += maf * dt
        }

        // Acceleration (km/h per second)
        var accel: Double = 0
        if let lastSpd = lastSpeed {
            accel = (speed - lastSpd) / dt
        }
        let jerk = lastAccel.map { abs(accel - $0) / dt } ?? 0

        if accel > mode.harshAccelKmHs && speed > 8 {
            harshAccelCount += 1
            accelPenalty += min(6, (accel - mode.harshAccelKmHs) * 0.8)
        }
        if accel < mode.harshBrakeKmHs && speed > 20 {
            harshBrakeCount += 1
            brakeEvents += 1
        }

        // Smoothness: penalize jerk spikes & aggressive pedal work
        let throttlePenalty = (sample.throttle.map { max(0, $0 - 60) } ?? 0) * 0.02
        accelPenalty = min(30, accelPenalty * 0.995 + jerk * 0.012 + throttlePenalty)
        components.smoothness = max(0, 100 - accelPenalty)

        // Anticipation: braking events per km
        if distanceKm > 0.2 {
            let perKm = brakeEvents / distanceKm
            components.anticipation = max(0, min(100, 100 - perKm * 9))
        }

        // Idle share
        if speed < 2 && rpm > 450 {
            idleSeconds += dt
        }
        let idleShare = idleSeconds / totalSeconds
        components.idle = max(0, 100 - idleShare * 320)

        // RPM discipline + speed discipline
        if rpm > mode.rpmCeiling {
            highRPMSecs += dt
        }
        if speed > 112 {
            fastSpeedSecs += dt
        }
        let rpmShare = highRPMSecs / totalSeconds
        let fastShare = fastSpeedSecs / totalSeconds
        components.speedDiscipline = max(0, 100 - rpmShare * 260 - fastShare * 160)

        // Efficiency: instant L/100km vs ideal curve (EMA-smoothed)
        if let maf = sample.maf, let instant = FuelMath.instantL100(maf: maf, speedKmh: speed, fuel: fuelType) {
            let ideal = FuelMath.idealL100(speedKmh: speed)
            let ratio = instant / max(ideal, 1)
            let inst = max(0, min(100, 118 - ratio * 62))
            effEMA = effEMA * 0.94 + inst * 0.06
        }
        components.efficiency = effEMA

        // Weighted overall
        let w = mode.scoreWeights
        let weighted = components.efficiency * w.0
            + components.smoothness * w.1
            + components.anticipation * w.2
            + components.idle * w.3
            + components.speedDiscipline * w.4
        overall = overall * 0.96 + weighted * 0.04

        lastAccel = accel
        return (components, overall)
    }

    var fuelUsedL: Double { fuelGrams / 745 }

    var distance: Double { distanceKm }

    var idleTime: Double { idleSeconds }
}
