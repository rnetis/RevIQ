import Foundation

/// Lightweight JSON persistence in the app's Documents directory.
/// (Chosen over Core Data to keep the project 100% source-buildable via XcodeGen/CI.)
final class PersistenceManager {

    static let shared = PersistenceManager()

    private let dir: URL

    private init() {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("RevIQData", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func url(_ name: String) -> URL {
        dir.appendingPathComponent(name)
    }

    // MARK: Trips

    func loadTrips() -> [Trip] {
        load([Trip].self, from: url("trips.json")) ?? []
    }

    func saveTrips(_ trips: [Trip]) {
        save(trips, to: url("trips.json"))
    }

    func addTrip(_ trip: Trip) {
        var trips = loadTrips()
        trips.insert(trip, at: 0)
        if trips.count > 400 { trips = Array(trips.prefix(400)) }
        saveTrips(trips)
    }

    func deleteTrip(id: UUID) {
        var trips = loadTrips()
        trips.removeAll { $0.id == id }
        saveTrips(trips)
    }

    func updateTrip(_ updated: Trip) {
        var trips = loadTrips()
        if let idx = trips.firstIndex(where: { $0.id == updated.id }) {
            trips[idx] = updated
        }
        saveTrips(trips)
    }

    // MARK: Maintenance

    func loadMaintenance() -> [MaintenanceItem] {
        if let items = load([MaintenanceItem].self, from: url("maintenance.json")) {
            return items
        }
        return [MaintenanceItem].defaults
    }

    func saveMaintenance(_ items: [MaintenanceItem]) {
        save(items, to: url("maintenance.json"))
    }

    // MARK: AI reports

    func loadAIReport(key: String) -> String? {
        load(AIReportStore.self, from: url("ai_reports.json"))?.reports[key]
    }

    func saveAIReport(key: String, text: String) {
        var store = load(AIReportStore.self, from: url("ai_reports.json")) ?? AIReportStore()
        store.reports[key] = text
        save(store, to: url("ai_reports.json"))
    }

    // MARK: Danger zone

    func clearAll() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    var storageSizeDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(Self.directorySize(dir)), countStyle: .file)
    }

    private static func directorySize(_ url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += size
            }
        }
        return total
    }

    // MARK: Generic

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

private struct AIReportStore: Codable {
    var reports: [String: String] = [:]
}

extension Array where Element == MaintenanceItem {
    static var defaults: [MaintenanceItem] {
        let now = Date()
        func item(_ title: String, _ icon: String, km: Double? = nil, months: Double? = nil) -> MaintenanceItem {
            MaintenanceItem(id: UUID(),
                            title: title,
                            icon: icon,
                            intervalKm: km,
                            intervalMonths: months,
                            lastServiceOdoKm: 0,
                            lastServiceDate: now,
                            notes: nil)
        }
        return [
            item("Engine oil & filter", "drop.fill", km: 10_000, months: 12),
            item("Engine air filter", "wind", km: 20_000),
            item("Cabin / pollen filter", "fanblades.fill", km: 15_000, months: 12),
            item("Spark plugs", "sparkles", km: 40_000),
            item("Brake fluid", "drop.triangle.fill", km: nil, months: 24),
            item("Engine coolant", "thermometer.medium", km: 60_000, months: 48),
            item("Transmission fluid", "gearshape.2.fill", km: 60_000),
            item("Tire rotation", "arrow.triangle.2.circlepath", km: 10_000)
        ]
    }
}
