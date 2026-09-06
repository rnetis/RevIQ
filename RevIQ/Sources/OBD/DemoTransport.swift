import Foundation

/// A fully simulated ELM327 adapter + car. Plugs into the same `OBDTransport`
/// interface, so the entire app (gauges, coach, analytics, DTC) runs without hardware.
final class DemoTransport: OBDTransport {

    let name = "Demo Vehicle (simulated)"

    private(set) var isConnected = false

    private var sessionStart = Date()
    private var lastTick = Date()
    private var distanceKm = 0.0
    private var faults = ["P0171", "P0420"]

    // Simulated vehicle state
    private(set) var speed: Double = 0
    private(set) var rpm: Double = 850
    private(set) var throttle: Double = 0

    func connect() async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
        sessionStart = Date()
        lastTick = Date()
        distanceKm = 0
        isConnected = true
    }

    func disconnect() {
        isConnected = false
    }

    // MARK: Command handling

    func send(_ command: String, timeout: TimeInterval = 2.0) async throws -> String {
        guard isConnected else { throw OBDError.notConnected }
        try await Task.sleep(nanoseconds: UInt64.random(in: 25_000_000...55_000_000))
        advance()
        return respond(to: command.uppercased().trimmingCharacters(in: .whitespaces))
    }

    private func respond(to cmd: String) -> String {
        if cmd == "ATZ" { return "ELM327 v1.5\r\r>" }
        if cmd.hasPrefix("AT") { return "OK\r\r>" }
        if cmd == "0100" { return "41 00 BE 3F A8 13\r\r>" }
        if cmd == "03" { return dtcResponse }
        if cmd == "04" {
            faults.removeAll()
            return "OK\r\r>"
        }
        if cmd == "010D" { return self.resp(pid: "0D", value: speed, bytes: 1, enc: .u8) }
        if cmd == "010C" { return self.resp(pid: "0C", value: rpm, bytes: 2, enc: .rpm) }
        if cmd == "0110" { return self.resp(pid: "10", value: maf, bytes: 2, enc: .hundred) }
        if cmd == "0111" { return self.resp(pid: "11", value: throttle, bytes: 1, enc: .percent) }
        if cmd == "0104" { return self.resp(pid: "04", value: engineLoad, bytes: 1, enc: .percent) }
        if cmd == "0105" { return self.resp(pid: "05", value: coolant, bytes: 1, enc: .offset40) }
        if cmd == "010F" { return self.resp(pid: "0F", value: intake, bytes: 1, enc: .offset40) }
        if cmd == "010B" { return self.resp(pid: "0B", value: map, bytes: 1, enc: .u8) }
        if cmd == "012F" { return self.resp(pid: "2F", value: fuelLevel, bytes: 1, enc: .percent) }
        if cmd == "010E" { return self.resp(pid: "0E", value: timing, bytes: 1, enc: .timing) }
        if cmd == "0106" { return self.resp(pid: "06", value: trimST, bytes: 1, enc: .trim) }
        if cmd == "0107" { return self.resp(pid: "07", value: trimLT, bytes: 1, enc: .trim) }
        if cmd == "0131" { return self.resp(pid: "31", value: odometerKm, bytes: 4, enc: .u32) }
        if cmd == "0142" { return self.resp(pid: "42", value: voltage, bytes: 2, enc: .thousand) }
        return "NO DATA\r\r>"
    }

    private var dtcResponse: String {
        if faults.isEmpty {
            return "43 00 00 00 00 00 00 00\r\r>"
        }
        var bytes: [String] = []
        for code in faults.prefix(3) {
            let sysBits: Int
            switch code.prefix(1) {
            case "C": sysBits = 1
            case "B": sysBits = 2
            case "U": sysBits = 3
            default: sysBits = 0
            }
            let digits = code.dropFirst()
            let d1 = Int(digits.prefix(1)) ?? 0
            let c3 = Int(digits.dropFirst().prefix(1)) ?? 0
            let rest2 = Int(digits.dropFirst(2).prefix(2), radix: 16) ?? 0
            let byteA = sysBits << 6 | d1 << 4 | c3
            let byteB = rest2
            bytes.append(String(format: "%02X", byteA))
            bytes.append(String(format: "%02X", byteB))
        }
        while bytes.count < 6 { bytes.append("00") }
        return "43 " + bytes.joined(separator: " ") + "\r\r>"
    }

    private enum ByteEnc { case u8, u32, rpm, hundred, thousand, percent, offset40, timing, trim }

    private func resp(pid: String, value: Double, bytes: Int, enc: ByteEnc) -> String {
        func hex(_ v: Int) -> String { String(format: "%02X", min(max(v, 0), 255)) }
        var a = 0, b = 0, c = 0, d = 0
        switch enc {
        case .u8: a = Int(value.rounded())
        case .rpm: let v = Int(value * 4); a = (v >> 8) & 0xFF; b = v & 0xFF
        case .hundred: let v = Int(value * 100); a = (v >> 8) & 0xFF; b = v & 0xFF
        case .thousand: let v = Int(value * 1000); a = (v >> 8) & 0xFF; b = v & 0xFF
        case .percent: a = Int(value * 255 / 100)
        case .offset40: a = Int(value + 40)
        case .timing: a = Int((value + 64) * 2)
        case .trim: a = Int(value * 128 / 100 + 128)
        case .u32: let v = Int(value); a = (v >> 24) & 0xFF; b = (v >> 16) & 0xFF; c = (v >> 8) & 0xFF; d = v & 0xFF
        }
        if bytes == 1 { return "41 \(pid) \(hex(a))\r\r>" }
        if bytes == 2 { return "41 \(pid) \(hex(a)) \(hex(b))\r\r>" }
        return "41 \(pid) \(hex(a)) \(hex(b)) \(hex(c)) \(hex(d))\r\r>"
    }

    // MARK: Physics simulation

    private var engineLoad: Double { min(100, throttle * 0.85 + rpm / 6500 * 25) }
    private var maf: Double { 1.4 + (rpm / 1000) * (1.9 + throttle * 0.055) }
    private var coolant: Double { min(92, 20 + elapsed * 0.22) }
    private var intake: Double { 31 + sin(elapsed / 23) * 2 }
    private var map: Double { 30 + throttle * 1.5 + rpm / 1000 * 4 }
    private var fuelLevel: Double { max(5, 64 - elapsed * 0.0035) }
    private var timing: Double { 9 + throttle * 0.12 }
    private var trimST: Double { sin(elapsed / 17) * 4.5 }
    private var trimLT: Double { sin(elapsed / 53) * 3.0 }
    private var voltage: Double { 14.1 + sin(elapsed / 9) * 0.08 }
    private var odometerKm: Double { 154_328 + distanceKm }
    private var elapsed: Double { Date().timeIntervalSince(sessionStart) }

    private func advance() {
        let now = Date()
        let dt = min(2.0, now.timeIntervalSince(lastTick))
        lastTick = now

        let cycle = elapsed.truncatingRemainder(dividingBy: 200)
        let (target, kind): (Double, String) = {
            switch cycle {
            case 0..<18: return (48, "accel")
            case 18..<40: return (48, "cruise")
            case 40..<48: return (0, "decel")
            case 48..<68: return (0, "idle")
            case 68..<78: return (95, "accel")
            case 78..<130: return (95, "cruise")
            case 130..<148: return (0, "decel")
            case 148..<158: return (0, "idle")
            case 158..<172: return (60, "accel")
            case 172..<186: return (60, "cruise")
            default: return (0, "decel")
            }
        }()

        // approach target speed
        let rate = 9.5
        if speed < target { speed = min(target, speed + rate * dt) }
        else if speed > target { speed = max(target, speed - (rate + 3) * dt) }
        speed = max(0, speed + Double.random(in: -0.4...0.4))

        distanceKm += speed * dt / 3600

        switch kind {
        case "accel": throttle = min(72, 28 + (target - speed) * 1.6 + Double.random(in: 0...6))
        case "cruise": throttle = 17 + Double.random(in: -2...2)
        case "decel": throttle = 0
        default: throttle = speed < 2 ? Double.random(in: 0...2) : 14
        }

        // pseudo-geared RPM
        let gears: [Double] = [0, 20, 38, 60, 85, 115, 1000]
        var low = gears[0], upper = gears[1]
        for i in 0..<gears.count - 1 where speed >= gears[i] {
            low = gears[i]; upper = gears[i + 1]
        }
        let frac = upper > low ? (speed - low) / (upper - low) : 0
        rpm = speed < 2
            ? 830 + Double.random(in: -25...25)
            : min(6400, max(900, 850 + frac * (2200 + throttle * 24) + throttle * 8))
    }
}
