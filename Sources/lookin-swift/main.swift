import Foundation

if CommandLine.arguments.contains("--selftest") {
    runSelfTest()
}

if CommandLine.arguments.contains("--devices") {
    do {
        let devices = try UsbMux.listDevices()
        print("USB devices: \(devices.map { "\($0.udid) (id \($0.deviceId))" })")
    } catch {
        print("usbmux error: \(error.localizedDescription)")
    }
    exit(0)
}

func describeTarget(_ t: DeviceTarget) -> String {
    switch t {
    case .auto: return "auto"
    case .simulator: return "simulator"
    case .device(let udid): return "device \(udid)"
    }
}

let server = MCPServer(name: "lookin-swift", version: "0.1.0")

let oidSchema: [String: Any] = [
    "type": "object",
    "properties": [
        "oid": ["type": "number", "description": "Target view object ID (from lookin_get_hierarchy)"],
    ],
    "required": ["oid"],
]

server.register(Tool(
    name: "lookin_get_hierarchy",
    description: "Return the running iOS app's UI view hierarchy tree (oid, className, frame, hidden, alpha) via official LookinServer. Requires the iOS app with LookinServer running in a booted simulator.",
    inputSchema: [
        "type": "object",
        "properties": [
            "maxDepth": ["type": "number", "description": "Maximum hierarchy depth. Returns all levels if omitted."],
        ],
    ],
    handler: { args in
        let maxDepth = (args["maxDepth"] as? NSNumber)?.intValue
        let json = try LookinClient.shared.getHierarchyJSON(maxDepth: maxDepth)
        return [textContent(json)]
    }
))

server.register(Tool(
    name: "lookin_get_attributes",
    description: "Query all UI attributes (identifier, attrType, value) of a view by oid, grouped by section. Get the oid from lookin_get_hierarchy first.",
    inputSchema: oidSchema,
    handler: { args in
        guard let oid = (args["oid"] as? NSNumber)?.uint64Value else {
            throw LookinError.message("Missing required argument: oid")
        }
        let json = try LookinClient.shared.getAttributesJSON(oid: oid)
        return [textContent(json)]
    }
))

server.register(Tool(
    name: "lookin_modify_attribute",
    description: "Modify a live UI property on the device. Calls a setter on the object at `oid`. Use `viewOid` from the hierarchy for UIView setters (setAlpha:, setHidden:, setBackgroundColor:, setFrame:), or `oid` (layer) for CALayer setters (setCornerRadius:, setOpacity:). value format by attrType: 14 BOOL=true/false; 12/13/5 number; 24 NSString=string; 17 CGPoint={x,y}; 19 CGSize={width,height}; 20 CGRect={x,y,width,height}; 27 UIColor={r,g,b,a} (0-1).",
    inputSchema: [
        "type": "object",
        "properties": [
            "oid": ["type": "number", "description": "Object ID of the view/layer to modify"],
            "setterSelector": ["type": "string", "description": "Objective-C setter, e.g. \"setAlpha:\", \"setHidden:\", \"setBackgroundColor:\""],
            "attrType": ["type": "number", "description": "LookinAttrType of the value (14 BOOL, 12 float, 13 double, 5 long, 24 NSString, 17 CGPoint, 19 CGSize, 20 CGRect, 27 UIColor)"],
            "value": ["description": "New value; shape depends on attrType (see tool description)"],
        ],
        "required": ["oid", "setterSelector", "attrType", "value"],
    ],
    handler: { args in
        guard let oid = (args["oid"] as? NSNumber)?.uint64Value else { throw LookinError.message("Missing required argument: oid") }
        guard let setter = args["setterSelector"] as? String else { throw LookinError.message("Missing required argument: setterSelector") }
        guard let attrType = (args["attrType"] as? NSNumber)?.intValue else { throw LookinError.message("Missing required argument: attrType") }
        guard let value = args["value"] else { throw LookinError.message("Missing required argument: value") }
        let result = try LookinClient.shared.modifyAttribute(oid: oid, setter: setter, attrType: attrType, value: value)
        return [textContent(result)]
    }
))

server.register(Tool(
    name: "lookin_list_devices",
    description: "List connectable iOS targets: booted simulators and USB-connected devices. Use before lookin_connect_device when more than one is available.",
    inputSchema: ["type": "object", "properties": [String: Any]()],
    handler: { _ in
        let devices = DeviceSelection.shared.list()
        let json = try LookinClient.jsonString([
            "devices": devices.map { ["udid": $0.udid, "name": $0.name, "type": $0.type] },
            "current": describeTarget(DeviceSelection.shared.target),
        ])
        return [textContent(json)]
    }
))

server.register(Tool(
    name: "lookin_connect_device",
    description: "Select which target the other tools connect to. Pass a device UDID (from lookin_list_devices), \"simulator\" for the booted simulator, or \"auto\" to auto-detect.",
    inputSchema: [
        "type": "object",
        "properties": [
            "target": ["type": "string", "description": "A device UDID, or \"simulator\", or \"auto\""],
        ],
        "required": ["target"],
    ],
    handler: { args in
        guard let target = args["target"] as? String else { throw LookinError.message("Missing required argument: target") }
        switch target.lowercased() {
        case "auto": DeviceSelection.shared.target = .auto
        case "simulator", "sim": DeviceSelection.shared.target = .simulator
        default: DeviceSelection.shared.target = .device(udid: target)
        }
        return [textContent("Target set to \(describeTarget(DeviceSelection.shared.target)).")]
    }
))

server.register(Tool(
    name: "lookin_get_screenshot",
    description: "Get a view's screenshot (PNG) by oid, from the hierarchy the app already rendered. Get the oid from lookin_get_hierarchy first.",
    inputSchema: oidSchema,
    handler: { args in
        guard let oid = (args["oid"] as? NSNumber)?.uint64Value else {
            throw LookinError.message("Missing required argument: oid")
        }
        let png = try LookinClient.shared.getScreenshotPNG(oid: oid)
        return [[
            "type": "image",
            "data": png.base64EncodedString(),
            "mimeType": "image/png",
        ]]
    }
))

FileHandle.standardError.write("[lookin-swift] started (LookinServer: simulator :47164-47169, USB device :47175-47179)\n".data(using: .utf8)!)
server.run()
