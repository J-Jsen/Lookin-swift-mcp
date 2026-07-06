import Foundation
import CoreGraphics

/// Offline self-check: `lookin-swift --selftest`.
///
/// We can't reach a real iOS app here, but we CAN validate the whole pipeline
/// except the live device semantics:
///   1. Peertalk framing round-trips over a socketpair.
///   2. A synthetic LookinServer response (archived under the real Lookin class
///      names) decodes through the exact production path into the expected JSON.
///
/// The synthetic response is built by encoding stand-in objects and remapping
/// their archived class names to LookinServer's, so NSKeyedUnarchiver on the
/// read side sees "LookinConnectionResponseAttachment" etc. — identical to what
/// the iOS framework sends.

// MARK: - Encoder stand-ins (write side)

final class EncObject: NSObject, NSCoding {
    let oid: UInt64; let classChain: [String]
    init(oid: UInt64, classChain: [String]) { self.oid = oid; self.classChain = classChain; super.init() }
    func encode(with c: NSCoder) {
        c.encode(NSNumber(value: oid), forKey: "oid")
        c.encode(classChain as NSArray, forKey: "classChainList")
    }
    required init?(coder: NSCoder) { return nil }
}

final class EncItem: NSObject, NSCoding {
    let view: EncObject; let frame: CGRect; let hidden: Bool; let alpha: Float; let subitems: [EncItem]
    init(view: EncObject, frame: CGRect, hidden: Bool, alpha: Float, subitems: [EncItem]) {
        self.view = view; self.frame = frame; self.hidden = hidden; self.alpha = alpha; self.subitems = subitems
        super.init()
    }
    func encode(with c: NSCoder) {
        c.encode(view, forKey: "viewObject")
        c.encode(subitems as NSArray, forKey: "subitems")
        c.encode(hidden, forKey: "hidden")
        c.encode(alpha, forKey: "alpha")
        c.encode(frame, forKey: "frame")
        c.encode(frame, forKey: "bounds")
    }
    required init?(coder: NSCoder) { return nil }
}

final class EncHierarchy: NSObject, NSCoding {
    let items: [EncItem]
    init(items: [EncItem]) { self.items = items; super.init() }
    func encode(with c: NSCoder) { c.encode(items as NSArray, forKey: "1") }
    required init?(coder: NSCoder) { return nil }
}

final class EncAttachment: NSObject, NSCoding {
    let data: EncHierarchy
    init(data: EncHierarchy) { self.data = data; super.init() }
    func encode(with c: NSCoder) {
        c.encode(data, forKey: "0")
        c.encode(NSNumber(value: 1), forKey: "dataTotalCount")
        c.encode(NSNumber(value: 1), forKey: "currentDataCount")
    }
    required init?(coder: NSCoder) { return nil }
}

private func makeSyntheticResponse() -> Data {
    let window = EncItem(
        view: EncObject(oid: 4001, classChain: ["UIWindow", "UIView", "NSObject"]),
        frame: CGRect(x: 0, y: 0, width: 390, height: 844), hidden: false, alpha: 1.0,
        subitems: [
            EncItem(view: EncObject(oid: 4002, classChain: ["UILabel", "UIView"]),
                    frame: CGRect(x: 10, y: 50, width: 100, height: 20), hidden: false, alpha: 0.5, subitems: []),
        ])
    let attachment = EncAttachment(data: EncHierarchy(items: [window]))

    let archiver = NSKeyedArchiver(requiringSecureCoding: false)
    // Remap our stand-in class names to the real LookinServer names.
    archiver.setClassName("LookinConnectionResponseAttachment", for: EncAttachment.self)
    archiver.setClassName("LookinHierarchyInfo", for: EncHierarchy.self)
    archiver.setClassName("LookinDisplayItem", for: EncItem.self)
    archiver.setClassName("LookinObject", for: EncObject.self)
    archiver.encode(attachment, forKey: NSKeyedArchiveRootObjectKey)
    archiver.finishEncoding()
    return archiver.encodedData
}

// MARK: - Tests

func runSelfTest() -> Never {
    var failures = 0
    func check(_ cond: Bool, _ label: String) {
        print("\(cond ? "PASS" : "FAIL"): \(label)")
        if !cond { failures += 1 }
    }

    // 1) Peertalk framing over a socketpair.
    do {
        var fds: [Int32] = [0, 0]
        socketpair(AF_UNIX, SOCK_STREAM, 0, &fds)
        let payload = "hello-frame".data(using: .utf8)!
        try Peertalk.sendFrame(fds[0], type: 202, tag: 7, payload: payload)
        let frame = try Peertalk.readFrame(fds[1])
        check(frame.type == 202 && frame.tag == 7 && frame.payload == payload, "Peertalk frame round-trip")
        close(fds[0]); close(fds[1])
    } catch {
        check(false, "Peertalk frame round-trip threw: \(error)")
    }

    // 2) Request encoding is a valid archive Foundation can read back.
    do {
        let req = try LookinClient.encodeRequest(["clientVersion": "1.2.8"])
        let back = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(req) as? [String: Any]
        check(back?["clientVersion"] as? String == "1.2.8", "request dict archive round-trip")
    } catch {
        check(false, "request encode threw: \(error)")
    }

    // 3) Full decode + JSON from a synthetic LookinServer response.
    do {
        let info = try LookinClient.decodeHierarchyInfo(from: makeSyntheticResponse())
        let json = try LookinClient.buildHierarchyJSON(info, maxDepth: nil)
        let obj = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
        let hierarchy = obj["hierarchy"] as! [[String: Any]]
        let root = hierarchy[0]
        let child = (root["children"] as! [[String: Any]])[0]
        check(obj["totalViews"] as? Int == 2, "totalViews == 2")
        check((root["oid"] as? NSNumber)?.uint64Value == 4001, "root oid")
        check(root["className"] as? String == "UIWindow", "root className")
        let frame = root["frame"] as! [Any]
        check((frame[2] as? NSNumber)?.doubleValue == 390, "root frame width")
        check((child["oid"] as? NSNumber)?.uint64Value == 4002, "child oid")
        check(child["className"] as? String == "UILabel", "child className")
        check((child["alpha"] as? NSNumber)?.doubleValue == 0.5, "child alpha")
        print("decoded JSON: \(json)")
    } catch {
        check(false, "hierarchy decode threw: \(error)")
    }

    print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
    exit(failures == 0 ? 0 : 1)
}
