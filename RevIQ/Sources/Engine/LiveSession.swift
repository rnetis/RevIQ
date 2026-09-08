import Foundation
import SwiftUI
import Combine

/// Central live engine: owns the OBD transport, polling loop, scoring, coaching,
/// trip accumulation and performance timers. One instance for the whole app.
@MainActor
final class LiveSession: ObservableObject {

    // MARK: Published state

    @Published var phase: ConnectPhase = .idle
    @Published var sample: Sample = .empty
    @Published var speedSeries: [TimeValue] = []
    @Published var rpmSeries: [TimeValue] = []
    @Published var throttleSeries: [TimeValue] = []
    @Published var fuelSeries: [TimeValue] = []
    @Published var ecoScore: Double = 100
    @Published var scoreComponents = ScoreComponents()
    @Published var currentTip: CoachTip?
    @Published var tipLog: [CoachTip] = []
    @Published var tripActive = false
    @Published var tripStats = LiveTripStats()
    @Published var timers: [PerfTimerResult] = []
    @Published var showAdapterPicker = false
    @Published var foundAdapters: [OBDAdapterInfo] = []
    @Published var scanning = false
    @Published var maintenance: [MaintenanceItem] = []

    private(set) var ble: ELM327BLE?
    private(set) var transport: OBDTransport?
    var settings: AppSettings?

    // MARK: Private

    private var pollTask: Task<Void, Never>?
    private var scoring = ScoringEngine()
    private var coach = OfflineCoach()
    private var perf = PerfTracker()
    private var previousSample: Sample?
    private var sessionStart = Date()
    private var cycleIndex = 0
    private var lastTripUpdate: Date?
    private var tripStartedAt = Date()
    private var tripSamples: [TripSample] = []
    private var lastTripSampleT: Double = -10
    private var harshAccelAtStart = 0
    private var harshBrakeAtStart = 0
    private var cancellables = Set<AnyCancellable>()

    private static let timersKey = "perfTimers"

    // MARK: Derived values

    var instantL100: Double? {
        guard let maf = sample.maf, let speed = sample.speed else { return nil }
        return FuelMath.instantL100(maf: maf, speedKmh: speed, fuel: settings?.vehicle.fuelType ?? .gasoline)
    }

    var litersPerHour: Double? {
        sample.maf.map { FuelMath.litersPerHour(maf: $0, fuel: settings?.vehicle.fuelType ?? .gasoline) }
    }

    var enginePowerKW: Double? {
        guard let maf = sample.maf, let rpm = sample.rpm else { return nil }
        return FuelMath.powerKW(maf: maf, rpm: rpm)
    }

    var hasData: Bool {
        sample.rpm != nil || sample.speed != nil
    }

    var perfArmed: Bool {
        perf.armed
    }

    var unitsConsumptionLabel: String {
        Format.consumptionUnit(settings?.units ?? .metric)
    }

    // MARK: Lifecycle

    func attach(settings: AppSettings) {
        if self.settings == nil { self.settings = settings }
        if maintenance.isEmpty {
            maintenance = PersistenceManager.shared.loadMaintenance()
        }
        if timers.isEmpty, let data = UserDefaults.standard.data(forKey: Self.timersKey),
           let saved = try? JSONDecoder().decode([PerfTimerResult].self, from: data) {
            timers = saved
        }
    }

    // MARK: Connection control

    func startDemo() {
        teardownTransport()
        let demo = DemoTransport()
        transport = demo
        phase = .demo
        Task {
            do {
                try await demo.connect()
                beginSession()
            } catch {
                phase = .failed(error.localizedDescription)
                transport = nil
            }
        }
    }

    func startBLE() {
        teardownTransport()
        let manager = ELM327BLE()
        ble = manager
        manager.$foundAdapters.receive(on: DispatchQueue.main).assign(to: &$foundAdapters)
        manager.$scanning.receive(on: DispatchQueue.main).assign(to: &$scanning)
        transport = manager
        foundAdapters = []
        phase = .scanning
        Task {
            let found = await manager.scan(timeout: 7)
            if found.isEmpty {
                phase = .failed("No ELM327 BLE adapters found. Plug the adapter into the car (ignition ON) and try again.")
                showAdapterPicker = true
            } else if found.count == 1 {
                await connectAdapter(found[0])
            } else {
                phase = .idle
                showAdapterPicker = true
            }
        }
    }

    func connectAdapter(_ info: OBDAdapterInfo) {
        guard let manager = ble else { return }
        phase = .connecting(info.name)
        Task {
            do {
                try await manager.connect(to: info)
                beginSession()
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func disconnect() {
        teardownTransport()
    }

    private func teardownTransport() {
        pollTask?.cancel()
        pollTask = nil
        transport?.disconnect()
        transport = nil
        ble = nil
        phase = .idle
        sample = .empty
        if tripActive { endTrip() }
    }

    private func beginSession() {
        sessionStart = Date()
        scoring.reset()
        coach.reset()
        perf = PerfTracker()
        previousSample = nil
        cycleIndex = 0
        speedSeries = []
        rpmSeries = []
        throttleSeries = []
        fuelSeries = []
        sample = .empty
        tipLog = []
        currentTip = nil
        startPolling()
    }

    // MARK: Polling loop

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            outer: while !Task.isCancelled {
                guard let self else { return }
                guard let transport = self.transport, transport.isConnected else { break }

                var pids = PIDSet.fastCycle
                if self.cycleIndex % 3 == 0 { pids += [PIDSet.coolant, PIDSet.intake, PIDSet.trimST] }
                if self.cycleIndex % 6 == 0 { pids += [PIDSet.fuelLevel, PIDSet.voltage, PIDSet.timing, PIDSet.trimLT] }
                if self.cycleIndex % 9 == 0 { pids += [PIDSet.distanceSinceCodesCleared] }

                for pid in pids {
                    if Task.isCancelled { break outer }
                    guard let current = self.transport, current.isConnected else { break outer }
                    do {
                        let raw = try await current.send("01" + pid.id, timeout: 2.2)
                        if let value = pid.decode(raw) {
                            self.apply(pidID: pid.id, value: value)
                        }
                    } catch {
                        self.phase = .failed(error.localizedDescription)
                        break outer
                    }
                    try? await Task.sleep(nanoseconds: 45_000_000)
                }
                self.cycleIndex += 1
            }
        }
    }

    // MARK: Sample application

    private func apply(pidID: String, value: Double) {
        var s = sample
        s.timestamp = Date()
        switch pidID {
        case "0C": s.rpm = value
        case "0D": s.speed = value
        case "11": s.throttle = value
        case "04": s.engineLoad = value
        case "05": s.coolant = value
        case "0F": s.intake = value
        case "10": s.maf = value
        case "0B": s.map = value
        case "2F": s.fuelLevel = value
        case "0E": s.timing = value
        case "06": s.trimST = value
        case "07": s.trimLT = value
        case "31": s.distanceSinceCodesClearedKm = value
        case "42": s.voltage = value
        default: break
        }
        sample = s

        guard pidID == "0D" || pidID == "0C" else { return }
        guard let speed = s.speed else { return }

        let t = Date().timeIntervalSince(sessionStart)
        appendTo(&speedSeries, t: t, v: speed, limit: 150)
        if let rpm = s.rpm { appendTo(&rpmSeries, t: t, v: rpm, limit: 150) }
        if let th = s.throttle { appendTo(&throttleSeries, t: t, v: th, limit: 150) }
        if let instant = instantL100 { appendTo(&fuelSeries, t: t, v: instant, limit: 150) }

        // Scoring
        let mode = settings?.preferredMode ?? .eco
        let fuel = settings?.vehicle.fuelType ?? .gasoline
        let (components, overall) = scoring.ingest(s, mode: mode, fuelType: fuel)
        scoreComponents = components
        ecoScore = overall

        // Perf timers (auto-arm when stopped with engine running; sportier weight everywhere)
        if let rpm = s.rpm, let results = perf.track(speed: speed, rpm: rpm) {
            for result in results {
                timers.insert(result, at: 0)
            }
            if timers.count > 12 { timers = Array(timers.prefix(12)) }
            persistTimers()
        }

        // Coach
        if let tip = coach.tick(s,
                                previous: previousSample,
                                mode: mode,
                                aiTipsEnabled: settings?.aiTipsEnabled ?? true,
                                chattiness: settings?.coachChattiness ?? 0.6) {
            currentTip = tip
            tipLog.insert(tip, at: 0)
            if tipLog.count > 8 { tipLog = Array(tipLog.prefix(8)) }
        }
        previousSample = s

        // Trip accumulation
        updateTrip(with: s)
    }

    private func appendTo(_ array: inout [TimeValue], t: TimeInterval, v: Double, limit: Int) {
        array.append(TimeValue(t: t, v: v))
        if array.count > limit { array.removeFirst(array.count - limit) }
    }

    // MARK: Trips

    private func updateTrip(with s: Sample) {
        guard tripActive else {
            lastTripUpdate = nil
            return
        }
        let now = s.timestamp
        defer { lastTripUpdate = now }

        guard let last = lastTripUpdate else { return }
        let dt = now.timeIntervalSince(last)
        guard dt > 0.05, dt < 5 else { return }

        tripStats.durationS += dt
        if let speed = s.speed {
            tripStats.distanceKm += speed * dt / 3600
            tripStats.maxSpeed = max(tripStats.maxSpeed, speed)
            if speed < 2, (s.rpm ?? 0) > 450 {
                tripStats.idleS += dt
            }
        }
        if let rpm = s.rpm {
            tripStats.maxRPM = max(tripStats.maxRPM, rpm)
        }
        if let maf = s.maf {
            let lph = FuelMath.litersPerHour(maf: maf, fuel: settings?.vehicle.fuelType ?? .gasoline)
            tripStats.fuelUsedL += lph * dt / 3600
        }
        tripStats.harshAccel = max(0, scoring.harshAccelCount - harshAccelAtStart)
        tripStats.harshBrake = max(0, scoring.harshBrakeCount - harshBrakeAtStart)

        let t = now.timeIntervalSince(tripStartedAt)
        if t - lastTripSampleT >= 3 {
            lastTripSampleT = t
            tripSamples.append(TripSample(t: t,
                                          s: s.speed ?? 0,
                                          r: s.rpm ?? 0,
                                          th: s.throttle ?? 0,
                                          f: instantL100))
        }
    }

    func startTrip() {
        guard phase.isLive, !tripActive else { return }
        tripStats = LiveTripStats(startedAt: Date())
        tripStartedAt = Date()
        tripSamples = []
        lastTripSampleT = -10
        lastTripUpdate = nil
        harshAccelAtStart = scoring.harshAccelCount
        harshBrakeAtStart = scoring.harshBrakeCount
        tripActive = true
        perf = PerfTracker()
    }

    func endTrip() {
        guard tripActive else { return }
        tripActive = false
        let trip = Trip(id: UUID(),
                        startedAt: tripStats.startedAt,
                        endedAt: Date(),
                        mode: settings?.preferredMode ?? .eco,
                        vehicleName: settings?.vehicle.displayName ?? "Car",
                        distanceKm: tripStats.distanceKm,
                        durationS: tripStats.durationS,
                        idleS: tripStats.idleS,
                        fuelUsedL: tripStats.fuelUsedL,
                        maxSpeed: tripStats.maxSpeed,
                        maxRPM: tripStats.maxRPM,
                        harshAccel: max(0, scoring.harshAccelCount - harshAccelAtStart),
                        harshBrake: max(0, scoring.harshBrakeCount - harshBrakeAtStart),
                        ecoScore: ecoScore,
                        samples: tripSamples,
                        aiSummary: nil)
        guard trip.distanceKm > 0.15 || trip.durationS > 45 else { return }
        PersistenceManager.shared.addTrip(trip)
    }

    func toggleTrip() {
        tripActive ? endTrip() : startTrip()
    }

    // MARK: Diagnostics

    func readDTCs() async -> [DTCCheck] {
        guard let transport, transport.isConnected else { return [] }
        do {
            let raw = try await transport.send("03", timeout: 3.5)
            let codes = OBDParser.decodeDTCs(raw)
            return codes.map {
                let info = DTCDatabase.title(for: $0)
                return DTCCheck(code: $0, title: info.title, known: info.known)
            }
        } catch {
            return []
        }
    }

    func clearDTCs() async -> Bool {
        guard let transport, transport.isConnected else { return false }
        let raw = (try? await transport.send("04", timeout: 3)) ?? ""
        return raw.uppercased().contains("OK")
    }

    // MARK: Timers

    func armTimer() {
        perf.arm()
    }

    func clearTimers() {
        timers = []
        persistTimers()
    }

    private func persistTimers() {
        if let data = try? JSONEncoder().encode(timers) {
            UserDefaults.standard.set(data, forKey: Self.timersKey)
        }
    }

    // MARK: Maintenance

    func markServiced(_ item: MaintenanceItem) {
        guard let idx = maintenance.firstIndex(where: { $0.id == item.id }) else { return }
        maintenance[idx].lastServiceDate = Date()
        maintenance[idx].lastServiceOdoKm = settings?.currentOdometerKm ?? 0
        PersistenceManager.shared.saveMaintenance(maintenance)
    }

    func addMaintenance(title: String, intervalKm: Double?, intervalMonths: Double?) {
        let item = MaintenanceItem(id: UUID(),
                                   title: title,
                                   icon: "wrench.and.screwdriver.fill",
                                   intervalKm: intervalKm,
                                   intervalMonths: intervalMonths,
                                   lastServiceOdoKm: settings?.currentOdometerKm ?? 0,
                                   lastServiceDate: Date(),
                                   notes: nil)
        maintenance.append(item)
        PersistenceManager.shared.saveMaintenance(maintenance)
    }

    func deleteMaintenance(_ item: MaintenanceItem) {
        maintenance.removeAll { $0.id == item.id }
        PersistenceManager.shared.saveMaintenance(maintenance)
    }
}

// MARK: - Performance tracker

/// Detects 0–60 mph / 0–100 km/h launches from the speed stream.
struct PerfTracker {
    private var stillSince: Date?
    private var launchStart: Date?
    private var captured: Set<Double> = []
    private(set) var armed = false

    private static let targets: [(speed: Double, label: String)] = [
        (96.56, "0–60 mph"),
        (100.0, "0–100 km/h")
    ]

    mutating func arm() {
        armed = true
        stillSince = nil
        launchStart = nil
        captured = []
    }

    mutating func track(speed: Double, rpm: Double) -> [PerfTimerResult]? {
        var results: [PerfTimerResult] = []

        if speed < 1.2 {
            if stillSince == nil { stillSince = Date() }
            if let since = stillSince,
               Date().timeIntervalSince(since) > 2,
               rpm > 400, !armed {
                arm()
            }
            return nil
        }

        guard armed else { return nil }

        if launchStart == nil, speed > 3 {
            launchStart = Date()
            captured = []
        }

        if let start = launchStart {
            for target in Self.targets where speed >= target.speed && !captured.contains(target.speed) {
                captured.insert(target.speed)
                results.append(PerfTimerResult(id: UUID(),
                                               date: Date(),
                                               label: target.label,
                                               seconds: Date().timeIntervalSince(start),
                                               topSpeed: speed))
            }
        }

        if captured.count >= Self.targets.count {
            armed = false
        }
        return results.isEmpty ? nil : results
    }
}
