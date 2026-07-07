import Foundation

/// Client for the LookinServer-Control command listener (:47180). Sends one
/// newline-delimited JSON command and reads the one-line JSON reply.
enum ControlClient {
    static let port = 47180

    /// Send a command dict and return true on success, throwing on failure.
    @discardableResult
    static func send(_ command: [String: Any]) throws -> Bool {
        let fd = try DeviceSelection.shared.connectPort(port)
        defer { close(fd) }

        var line = try JSONSerialization.data(withJSONObject: command)
        line.append(0x0A) // newline
        try Peertalk.writeAll(fd, line)

        let respData = try readLine(fd)
        guard let obj = try JSONSerialization.jsonObject(with: respData) as? [String: Any] else {
            throw LookinError.message("Bad response from LookinServer-Control")
        }
        if (obj["ok"] as? Bool) == true { return true }
        throw LookinError.message("LookinServer-Control: \(obj["error"] as? String ?? "injection failed")")
    }

    private static func readLine(_ fd: Int32) throws -> Data {
        var buf = Data()
        var byte: UInt8 = 0
        while true {
            let n = Darwin.read(fd, &byte, 1)
            if n <= 0 { break }
            if byte == 0x0A { break }
            buf.append(byte)
        }
        if buf.isEmpty { throw LookinError.message("No response from LookinServer-Control (is the pod integrated and the app in the foreground?)") }
        return buf
    }
}
