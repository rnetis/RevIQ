import Foundation

// MARK: - ELM327 response parsing

enum OBDParser {

    static let errorKeywords = [
        "NO DATA", "CAN ERROR", "BUS ERROR", "BUS INIT", "STOPPED",
        "UNABLE TO CONNECT", "DATA ERROR", "FB ERROR", "LV RESET", "?"
    ]

    /// Converts raw ELM327 output into a clean uppercase hex string.
    /// Handles echo, prompt chars, "SEARCHING…" lines, multiline frames ("0:" "1:") and errors.
    static func clean(_ raw: String) -> (hex: String, error: Bool) {
        var hexOut = ""
        var hadError = false
        let lines = raw
            .replacingOccurrences(of: ">", with: "\n")
            .components(separatedBy: CharacterSet(charactersIn: "\r\n"))

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let upper = line.uppercased()

            if upper.contains("SEARCHING") { continue }
            if upper.contains("ELM") { continue }
            if upper == "OK" { continue }

            var isErrorLine = false
            for keyword in errorKeywords where upper.contains(keyword) {
                isErrorLine = true
                break
            }
            if isErrorLine {
                // "BUS INIT...OK" is a success message, not an error.
                if upper.contains("BUS INIT") && upper.contains("OK") { continue }
                hadError = true
                continue
            }

            // Multiline ISO-TP frames: "0: 41 00 BE 3F A8 10" → drop "0:" index
            var work = line
            if work.count >= 2, let first = work.first, first.isNumber,
               work.dropFirst().first == ":" {
                work = String(work.dropFirst(2))
            }

            hexOut += work.filter { $0.isHexDigit }.uppercased()
        }
        return (hexOut, hadError)
    }

    /// Finds "41 XX" response data for the requested PID and returns the following bytes.
    static func payloadBytes(forPID pid: String, in raw: String) -> [UInt8]? {
        let hex = clean(raw).hex
        guard hex.count >= 6 else { return nil }
        let header = "41" + pid.uppercased()
        var searchRange = hex.startIndex..<hex.endIndex
        while let r = hex.range(of: header, range: searchRange) {
            let after = r.upperBound
            let remaining = hex[after...]
            if remaining.count >= 2 {
                var bytes: [UInt8] = []
                var idx = remaining.startIndex
                while idx < remaining.endIndex, bytes.count < 8 {
                    let next = hex.index(idx, offsetBy: 2, limitedBy: remaining.endIndex) ?? remaining.endIndex
                    if next == idx { break }
                    if let b = UInt8(hex[idx..<next], radix: 16) { bytes.append(b) }
                    idx = next
                }
                if !bytes.isEmpty { return bytes }
            }
            searchRange = r.upperBound..<hex.endIndex
            if searchRange.isEmpty { break }
        }
        return nil
    }

    /// Parses Mode $03 response into DTC strings ("P0171", …).
    static func decodeDTCs(_ raw: String) -> [String] {
        let hex = clean(raw).hex.uppercased()
        var codes: [String] = []
        guard let r = hex.range(of: "43") else { return codes }
        var payload = String(hex[r.upperBound...])
        // Some ECUs pad with 55s / 00s — trim non-dtc padding patterns conservatively.
        while payload.count >= 4 {
            let idx = payload.index(payload.startIndex, offsetBy: 4)
            let byteStr = String(payload[..<idx])
            payload = String(payload[idx...])
            guard let b = UInt32(byteStr, radix: 16) else { continue }
            if b == 0 { continue }
            let systems = ["P", "C", "B", "U"]
            let sysIdx = Int((b >> 14) & 0x03)
            let d1 = Int((b >> 12) & 0x03)
            let rest = String(format: "%01X%01X%01X",
                              Int((b >> 8) & 0x0F),
                              Int((b >> 4) & 0x0F),
                              Int(b & 0x0F))
            codes.append(systems[sysIdx] + String(d1) + rest)
        }
        return codes
    }
}

// MARK: - PID definitions (SAE J1979)

struct PID {
    let id: String          // e.g. "0C"
    let name: String
    let unit: String
    let decode: (String) -> Double?

    static func b(_ bytes: [UInt8], _ i: Int) -> Double? {
        guard bytes.count > i else { return nil }
        return Double(bytes[i])
    }
}

enum PIDSet {

    static let rpm = PID(id: "0C", name: "Engine RPM", unit: "rpm") { raw in
        guard let b = OBDParser.payloadBytes(forPID: "0C", in: raw), b.count >= 2 else { return nil }
        return (Double(b[0]) * 256 + Double(b[1])) / 4
    }

    static let speed = PID(id: "0D", name: "Vehicle speed", unit: "km/h") { raw in
        guard let b = OBDParser.payloadBytes(forPID: "0D", in: raw) else { return nil }
        return Double(b[0])
    }

    static let throttle = PID(id: "11", name: "Throttle position", unit: "%") { raw in
        guard let b = OBDParser.payloadBytes(forPID: "11", in: raw) else { return nil }
        return Double(b[0]) * 100 / 255
    }

    static let engineLoad = PID(id: "04", name: "Engine load", unit: "%") { raw in
        guard let b = OBDParser.payloadBytes(forPID: "04", in: raw) else { return nil }
        return Double(b[0]) * 100 / 255
    }

    static let coolant = PID(id: "05", name: "Coolant temp", unit: "°C") { raw in
        guard let b = OBDParser.payloadBytes(forPID: "05", in: raw) else { return nil }
        return Double(b[0]) - 40
    }

    static let intake = PID(id: "0F", name: "Intake temp", unit: "°C") { raw in
        guard let b = OBDParser.payloadBytes(forPID: "0F", in: raw) else { return nil }
        return Double(b[0]) - 40
    }

    static let maf = PID(id: "10", name: "Air flow (MAF)", unit: "g/s") { raw in
        guard let b = OBDParser.payloadBytes(forPID: "10", in: raw), b.count >= 2 else { return nil }
        return (Double(b[0]) * 256 + Double(b[1])) / 100
    }

    static let map = PID(id: "0B", name: "Intake manifold pressure", unit: "kPa") { raw in
        guard let b = OBDParser.payloadBytes(forPID: "0B", in: raw) else { return nil }
        return Double(b[0])
    }

    static let fuelLevel = PID(id: "2F", name: "Fuel level", unit: "%") { raw in
        guard let b = OBDParser.payloadBytes(forPID: "2F", in: raw) else { return nil }
        return Double(b[0]) * 100 / 255
    }

    static let timing = PID(id: "0E", name: "Timing advance", unit: "°") { raw in
        guard let b = OBDParser.payloadBytes(forPID: "0E", in: raw) else { return nil }
        return Double(b[0]) / 2 - 64
    }

    static let trimST = PID(id: "06", name: "Short-term fuel trim", unit: "%") { raw in
        guard let b = OBDParser.payloadBytes(forPID: "06", in: raw) else { return nil }
        return (Double(b[0]) - 128) * 100 / 128
    }

    static let trimLT = PID(id: "07", name: "Long-term fuel trim", unit: "%") { raw in
        guard let b = OBDParser.payloadBytes(forPID: "07", in: raw) else { return nil }
        return (Double(b[0]) - 128) * 100 / 128
    }

    static let odo = PID(id: "31", name: "Odometer", unit: "km") { raw in
        guard let b = OBDParser.payloadBytes(forPID: "31", in: raw), b.count >= 4 else { return nil }
        return Double(b[0]) * 16_777_216 + Double(b[1]) * 65_536 + Double(b[2]) * 256 + Double(b[3])
    }

    static let voltage = PID(id: "42", name: "Control module voltage", unit: "V") { raw in
        guard let b = OBDParser.payloadBytes(forPID: "42", in: raw), b.count >= 2 else { return nil }
        return (Double(b[0]) * 256 + Double(b[1])) / 1000
    }

    /// Polled every cycle — used for gauges, scoring and fuel math.
    static let fastCycle: [PID] = [speed, rpm, maf, throttle, engineLoad, map]

    /// Polled every few cycles — slow-changing signals.
    static let slowCycle: [PID] = [coolant, intake, fuelLevel, timing, voltage, odo, trimST, trimLT]

    static func byID(_ id: String) -> PID? {
        (fastCycle + slowCycle).first { $0.id == id }
    }
}
