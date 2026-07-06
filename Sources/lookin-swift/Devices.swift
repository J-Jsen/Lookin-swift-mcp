import Foundation

/// Which LookinServer the tools should connect to.
enum DeviceTarget: Equatable {
    case auto                 // simulator first, then first USB device
    case simulator            // booted simulator only
    case device(udid: String) // a specific USB device
}

/// Holds the current connection target (set via lookin_connect_device) and
/// resolves it to a live socket for the Peertalk client.
final class DeviceSelection {
    static let shared = DeviceSelection()
    var target: DeviceTarget = .auto

    struct DeviceInfo {
        let udid: String
        let name: String
        let type: String // "simulator" | "physical"
    }

    /// Booted simulators (via simctl) + USB devices (via usbmux).
    func list() -> [DeviceInfo] {
        var result: [DeviceInfo] = []
        for sim in Self.bootedSimulators() {
            result.append(DeviceInfo(udid: sim.udid, name: sim.name, type: "simulator"))
        }
        if let usb = try? UsbMux.listDevices() {
            for d in usb {
                result.append(DeviceInfo(udid: d.udid, name: d.udid, type: "physical"))
            }
        }
        return result
    }

    /// Connect honoring the current target. Returns a socket fd for Peertalk.
    func connect() throws -> Int32 {
        switch target {
        case .simulator:
            return try connectSimulator()
        case .device(let udid):
            return try connectDevice(udid: udid)
        case .auto:
            if let fd = try? connectSimulator() { return fd }
            return try connectFirstDevice()
        }
    }

    // MARK: - Helpers

    private func connectSimulator() throws -> Int32 {
        for port in Peertalk.simulatorPorts {
            if let fd = try? Peertalk.connect(host: "127.0.0.1", port: port) { return fd }
        }
        throw LookinError.message("No LookinServer on a booted simulator (ports \(Peertalk.simulatorPorts.lowerBound)-\(Peertalk.simulatorPorts.upperBound)). Is the app running in the foreground?")
    }

    private func connectDevice(udid: String) throws -> Int32 {
        let devices = try UsbMux.listDevices()
        guard let dev = devices.first(where: { $0.udid == udid }) else {
            throw LookinError.message("USB device \(udid) not found. Run lookin_list_devices to see connected devices.")
        }
        return try connectToDevicePorts(dev.deviceId)
    }

    private func connectFirstDevice() throws -> Int32 {
        if let devices = try? UsbMux.listDevices() {
            for dev in devices {
                if let fd = try? connectToDevicePorts(dev.deviceId) { return fd }
            }
        }
        throw LookinError.message("Cannot reach LookinServer. Start the app (with pod 'LookinServer') in a booted simulator, or connect a USB device and run it in the foreground.")
    }

    private func connectToDevicePorts(_ deviceId: Int) throws -> Int32 {
        for port in UsbMux.devicePorts {
            if let fd = try? UsbMux.connectToDevice(deviceId: deviceId, port: port) { return fd }
        }
        throw LookinError.message("Connected to device but no LookinServer port (\(UsbMux.devicePorts.lowerBound)-\(UsbMux.devicePorts.upperBound)) is open. Is the app in the foreground?")
    }

    private static func bootedSimulators() -> [(udid: String, name: String)] {
        guard let out = try? runSimctl() else { return [] }
        guard let data = out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [String: Any] else { return [] }
        var result: [(String, String)] = []
        for (_, list) in devices {
            for dev in (list as? [[String: Any]]) ?? [] where (dev["state"] as? String) == "Booted" {
                if let udid = dev["udid"] as? String, let name = dev["name"] as? String {
                    result.append((udid, name))
                }
            }
        }
        return result
    }

    private static func runSimctl() throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        proc.arguments = ["simctl", "list", "devices", "booted", "--json"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
