import Foundation

/// Peertalk framing client.
///
/// LookinServer (the iOS framework) listens on a loopback TCP port and speaks
/// Peertalk: each message is a 16-byte header of four big-endian UInt32
/// (version=1, type, tag, payloadSize) followed by `payloadSize` payload bytes
/// (an NSKeyedArchiver blob). See Lookin_PTProtocol.m.
///
/// We are the *client* (the role Lookin.app plays): connect over TCP, send a
/// request frame, read the response frame with the same tag.
enum Peertalk {
    static let protocolVersion: UInt32 = 1
    static let frameTypeEndOfStream: UInt32 = .max

    /// Simulator: LookinServer tries ports 47164...47169 in order.
    static let simulatorPorts: ClosedRange<Int> = 47164...47169

    /// Connect to LookinServer wherever it is: prefer a booted simulator
    /// (loopback TCP), otherwise tunnel to the first USB device via usbmux.
    /// Returns a socket fd ready for Peertalk frames.
    static func connectLookinServer() throws -> Int32 {
        // Simulator: fast loopback probe.
        for port in simulatorPorts {
            if let fd = try? connect(host: "127.0.0.1", port: port) {
                return fd
            }
        }
        // Physical device via usbmux (ignored if usbmuxd/devices unavailable).
        if let devices = try? UsbMux.listDevices() {
            for device in devices {
                for port in UsbMux.devicePorts {
                    if let fd = try? UsbMux.connectToDevice(deviceId: device.deviceId, port: port) {
                        return fd
                    }
                }
            }
        }
        throw LookinError.message(
            "Cannot reach LookinServer. Make sure the iOS app (with pod 'LookinServer') is running in the foreground in a booted simulator, or connected via USB and trusted on this Mac.")
    }

    struct Frame {
        let type: UInt32
        let tag: UInt32
        let payload: Data
    }

    static func connect(host: String, port: Int) throws -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LookinError.message("socket() failed") }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr(host)

        let rc = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if rc != 0 {
            close(fd)
            throw LookinError.message("connect() to \(host):\(port) failed")
        }
        return fd
    }

    // MARK: - Frame I/O

    static func sendFrame(_ fd: Int32, type: UInt32, tag: UInt32, payload: Data) throws {
        var header = Data(capacity: 16)
        for value in [protocolVersion, type, tag, UInt32(payload.count)] {
            var be = value.bigEndian
            withUnsafeBytes(of: &be) { header.append(contentsOf: $0) }
        }
        try writeAll(fd, header)
        if !payload.isEmpty {
            try writeAll(fd, payload)
        }
    }

    static func readFrame(_ fd: Int32) throws -> Frame {
        let header = try readAll(fd, count: 16)
        let fields: [UInt32] = stride(from: 0, to: 16, by: 4).map { offset in
            let slice = header.subdata(in: offset..<(offset + 4))
            return slice.withUnsafeBytes { UInt32(bigEndian: $0.load(as: UInt32.self)) }
        }
        let version = fields[0], type = fields[1], tag = fields[2], size = fields[3]
        guard version == protocolVersion else {
            throw LookinError.message("Unexpected Peertalk version \(version)")
        }
        let payload = size > 0 ? try readAll(fd, count: Int(size)) : Data()
        return Frame(type: type, tag: tag, payload: payload)
    }

    // MARK: - Blocking full read/write

    static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            var sent = 0
            let total = buf.count
            let base = buf.baseAddress!
            while sent < total {
                let n = Darwin.write(fd, base + sent, total - sent)
                if n <= 0 { throw LookinError.message("socket write failed") }
                sent += n
            }
        }
    }

    static func readAll(_ fd: Int32, count: Int) throws -> Data {
        var result = Data(count: count)
        try result.withUnsafeMutableBytes { (buf: UnsafeMutableRawBufferPointer) in
            var got = 0
            let base = buf.baseAddress!
            while got < count {
                let n = Darwin.read(fd, base + got, count - got)
                if n == 0 { throw LookinError.message("LookinServer closed the connection unexpectedly") }
                if n < 0 { throw LookinError.message("socket read failed") }
                got += n
            }
        }
        return result
    }
}
