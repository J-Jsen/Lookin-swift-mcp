import Foundation

/// Minimal usbmuxd client for tunneling to LookinServer on a physical device.
///
/// macOS ships a usbmuxd daemon on the /var/run/usbmuxd unix socket. Through it
/// we can list USB devices and open a transparent TCP tunnel to a port on a
/// device. Message framing is:
///   [4B totalLen LE][4B version=1][4B msgType=8 (plist)][4B tag LE][plist body]
/// The plist body is read/written natively with PropertyListSerialization — no
/// plutil subprocess or third-party bplist code needed.
enum UsbMux {
    private static let socketPath = "/var/run/usbmuxd"
    /// LookinServer on a USB device listens on 47175...47179 (LookinDefines.h).
    static let devicePorts: ClosedRange<Int> = 47175...47179

    struct Device {
        let deviceId: Int
        let udid: String
    }

    // MARK: - Public

    /// List iOS devices currently connected over USB (skips Wi-Fi entries).
    static func listDevices() throws -> [Device] {
        let fd = try connectSocket()
        defer { close(fd) }
        let resp = try sendReceive(fd, ["MessageType": "ListDevices"])
        guard let list = resp["DeviceList"] as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let props = entry["Properties"] as? [String: Any],
                  (props["ConnectionType"] as? String) == "USB",
                  let id = entry["DeviceID"] as? Int,
                  let udid = props["SerialNumber"] as? String else { return nil }
            return Device(deviceId: id, udid: udid)
        }
    }

    /// Open a tunnel to `port` on `deviceId`. On success the returned fd IS the
    /// tunnel: send Peertalk frames over it directly.
    static func connectToDevice(deviceId: Int, port: Int) throws -> Int32 {
        let fd = try connectSocket()
        // usbmuxd wants the port in network byte order.
        let portBE = ((port & 0xff) << 8) | ((port >> 8) & 0xff)
        let resp = try sendReceive(fd, [
            "MessageType": "Connect",
            "DeviceID": deviceId,
            "PortNumber": portBE,
        ])
        let code = (resp["Number"] as? Int) ?? -1
        if code != 0 {
            close(fd)
            let reason: String
            switch code {
            case 3: reason = "port not open on device (is the app with LookinServer in the foreground?)"
            case 2: reason = "device not connected"
            default: reason = "usbmux error code \(code)"
            }
            throw LookinError.message("usbmux Connect to device port \(port) failed: \(reason)")
        }
        return fd
    }

    // MARK: - Socket

    private static func connectSocket() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LookinError.message("usbmuxd: socket() failed") }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8CString) // includes trailing NUL
        withUnsafeMutableBytes(of: &addr.sun_path) { dst in
            precondition(pathBytes.count <= dst.count, "usbmuxd socket path too long")
            pathBytes.withUnsafeBytes { src in
                dst.copyMemory(from: src)
            }
        }
        let rc = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if rc != 0 {
            close(fd)
            throw LookinError.message("usbmuxd not available at \(socketPath)")
        }
        return fd
    }

    // MARK: - Plist message I/O

    private static func sendReceive(_ fd: Int32, _ payload: [String: Any]) throws -> [String: Any] {
        try sendPlist(fd, payload)
        return try readPlist(fd)
    }

    private static func sendPlist(_ fd: Int32, _ payload: [String: Any]) throws {
        let body = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
        var header = Data(capacity: 16)
        appendLE(&header, UInt32(16 + body.count)) // total length
        appendLE(&header, UInt32(1))               // version = 1
        appendLE(&header, UInt32(8))               // msgType = 8 (plist)
        appendLE(&header, UInt32(1))               // tag
        try Peertalk.writeAll(fd, header)
        try Peertalk.writeAll(fd, body)
    }

    private static func readPlist(_ fd: Int32) throws -> [String: Any] {
        let header = try Peertalk.readAll(fd, count: 16)
        let totalLen = header.withUnsafeBytes { UInt32(littleEndian: $0.load(as: UInt32.self)) }
        guard totalLen >= 16 else { throw LookinError.message("usbmuxd: bad response length") }
        let body = try Peertalk.readAll(fd, count: Int(totalLen) - 16)
        guard let plist = try PropertyListSerialization.propertyList(from: body, options: [], format: nil) as? [String: Any] else {
            throw LookinError.message("usbmuxd: response is not a plist dictionary")
        }
        return plist
    }

    private static func appendLE(_ data: inout Data, _ value: UInt32) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }
}
