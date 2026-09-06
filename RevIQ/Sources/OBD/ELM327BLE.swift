import Foundation
import CoreBluetooth

// MARK: - Errors & transport protocol

enum OBDError: LocalizedError {
    case notConnected
    case timeout
    case adapterError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Adapter is not connected."
        case .timeout: return "Adapter did not respond in time."
        case .adapterError(let m): return m
        }
    }
}

protocol OBDTransport: AnyObject {
    var name: String { get }
    var isConnected: Bool { get }
    func connect() async throws
    func send(_ command: String, timeout: TimeInterval) async throws -> String
    func disconnect()
}

extension OBDTransport {
    func send(_ command: String) async throws -> String {
        try await send(command, timeout: 2.0)
    }
}

// MARK: - Adapter discovery model

struct OBDAdapterInfo: Identifiable, Hashable {
    let id: UUID
    let name: String
    let rssi: Int
    let serviceUUIDs: [String]
}

// MARK: - ELM327 over BLE

/// Handles scanning, pairing and the ELM327 AT/protocol conversation over a BLE UART.
final class ELM327BLE: NSObject, ObservableObject, OBDTransport {

    static let knownServiceIDs = ["FFE0", "FFF0", "18F0", "FFF5", "FFE5"]
    static let knownNameHints = [
        "OBD", "OBDII", "OBD2", "ELM", "V-LINK", "VLINK", "VEEPEAK", "VGATE",
        "ICAR", "IOS-VLINK", "CARLY", "OBDLINK", "KONNWEI", "ANCEL", "LAUNCH",
        "V01H2", "VEEPLY", "BLUEDRIVER", "VGGPS", "LELINK"
    ]

    @Published var phase: ConnectPhase = .idle
    @Published var foundAdapters: [OBDAdapterInfo] = []
    @Published var scanning = false

    var name: String { targetName ?? "ELM327 BLE" }
    private var targetName: String?
    private(set) var isConnected = false

    private var central: CBCentralManager?
    private var target: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?

    private var discovered: [UUID: CBPeripheral] = [:]
    private var rxBuffer = ""
    private var peripheralConnected = false
    private var servicesReady = false

    // MARK: Scanning

    /// Scans for known ELM327-style adapters. Returns after `timeout` seconds;
    /// `foundAdapters` is updated live while scanning.
    func scan(timeout: TimeInterval) async -> [OBDAdapterInfo] {
        foundAdapters = []
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        }
        let bootDeadline = Date().addingTimeInterval(4)
        while central!.state != .poweredOn && Date() < bootDeadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard central!.state == .poweredOn else {
            phase = .failed("Bluetooth is off or unavailable")
            scanning = false
            return []
        }
        scanning = true
        phase = .scanning
        central?.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        central?.stopScan()
        scanning = false
        return foundAdapters
    }

    func stopScan() {
        central?.stopScan()
        scanning = false
    }

    // MARK: OBDTransport

    func connect() async throws {
        guard let best = foundAdapters.max(by: { $0.rssi < $1.rssi }) else {
            throw OBDError.adapterError("No adapter found — scan first.")
        }
        try await connect(to: best)
    }

    func connect(to info: OBDAdapterInfo) async throws {
        phase = .connecting(info.name)
        targetName = info.name

        guard let central, central.state == .poweredOn else {
            throw OBDError.adapterError("Bluetooth is off")
        }

        let peripheral = discovered[info.id]
            ?? central.retrievePeripherals(withIdentifiers: [info.id]).first
        guard let peripheral else {
            throw OBDError.adapterError("Adapter lost — scan again")
        }

        target = peripheral
        peripheral.delegate = self
        peripheralConnected = false
        servicesReady = false
        central.connect(peripheral)

        var deadline = Date().addingTimeInterval(14)
        while !peripheralConnected && Date() < deadline {
            try await Task.sleep(nanoseconds: 120_000_000)
        }
        guard peripheralConnected else {
            central.cancelPeripheralConnection(peripheral)
            throw OBDError.adapterError("Could not connect to \(info.name)")
        }

        peripheral.discoverServices(nil)
        deadline = Date().addingTimeInterval(10)
        while !servicesReady && Date() < deadline {
            try await Task.sleep(nanoseconds: 120_000_000)
        }
        guard servicesReady, writeChar != nil, notifyChar != nil else {
            throw OBDError.adapterError("Adapter has no serial service (try a different UART adapter)")
        }

        try await runInitSequence()
        isConnected = true
        phase = .connected(info.name)
    }

    func send(_ command: String, timeout: TimeInterval = 2.0) async throws -> String {
        guard let peripheral = target, let writeChar,
              peripheral.state == .connected else {
            throw OBDError.notConnected
        }
        rxBuffer = ""
        writeChunked(Data((command + "\r").utf8), peripheral: peripheral, char: writeChar)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if rxBuffer.contains(">") { return rxBuffer }
            if peripheral.state != .connected { throw OBDError.notConnected }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        throw OBDError.timeout
    }

    func disconnect() {
        if let p = target { central?.cancelPeripheralConnection(p) }
        isConnected = false
        phase = .idle
    }

    // MARK: Internals

    private func writeChunked(_ data: Data, peripheral: CBPeripheral, char: CBCharacteristic) {
        let mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
        let size = mtu > 0 ? min(mtu, 20) : 20
        var offset = 0
        while offset < data.count {
            let end = min(offset + size, data.count)
            let chunk = data.subdata(in: offset..<end)
            peripheral.writeValue(chunk, for: char, type: .withoutResponse)
            offset = end
            Thread.sleep(forTimeInterval: 0.012)
        }
    }

    private func runInitSequence() async throws {
        let sequence: [(cmd: String, timeout: TimeInterval, settle: UInt64)] = [
            ("ATZ", 3.2, 800_000_000),
            ("ATE0", 1.6, 120_000_000),
            ("ATL0", 1.2, 120_000_000),
            ("ATS0", 1.2, 120_000_000),
            ("ATH0", 1.2, 120_000_000),
            ("ATAT1", 1.2, 120_000_000),
            ("ATSP0", 2.5, 200_000_000)
        ]
        for step in sequence {
            _ = try? await send(step.cmd, timeout: step.timeout)
            try? await Task.sleep(nanoseconds: step.settle)
        }
    }

    private func handleLostConnection() {
        guard isConnected else { return }
        isConnected = false
        phase = .failed("Adapter disconnected")
        target = nil
        writeChar = nil
        notifyChar = nil
    }
}

// MARK: - CBCentralManagerDelegate

extension ELM327BLE: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            scanning = false
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "Unknown"
        guard name != "Unknown" else { return }

        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
            .map { $0.uuidString.uppercased() } ?? []

        let nameHit = ELM327BLE.knownNameHints.contains { name.uppercased().contains($0) }
        let serviceHit = services.contains { ELM327BLE.knownServiceIDs.contains($0) }

        guard nameHit || serviceHit else { return }

        discovered[peripheral.identifier] = peripheral
        let info = OBDAdapterInfo(id: peripheral.identifier,
                                  name: name,
                                  rssi: RSSI.intValue,
                                  serviceUUIDs: services)
        if !foundAdapters.contains(info) {
            foundAdapters.append(info)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheralConnected = true
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        peripheralConnected = false
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        if peripheral == target {
            handleLostConnection()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension ELM327BLE: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        for characteristic in service.characteristics ?? [] {
            if characteristic.properties.contains(.notify) {
                notifyChar = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if characteristic.properties.contains(.writeWithoutResponse)
                || characteristic.properties.contains(.write) {
                writeChar = characteristic
            }
        }
        if notifyChar != nil && writeChar != nil {
            servicesReady = true
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value,
              let text = String(data: data, encoding: .ascii) ?? String(data: data, encoding: .utf8)
        else { return }
        rxBuffer += text
    }
}
