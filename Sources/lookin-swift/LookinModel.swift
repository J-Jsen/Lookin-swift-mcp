import Foundation

/// Placeholder NSCoding classes.
///
/// LookinServer archives its own Objective-C model objects with NSKeyedArchiver.
/// We don't have those classes on macOS, so we register lightweight stand-ins
/// under the same archived class names; NSKeyedUnarchiver then instantiates
/// these and reads the exact same coding keys the iOS side wrote. Foundation
/// containers (NSArray/NSString/NSNumber) decode natively.
///
/// The Hierarchy(202) response only carries structure (no attributes/
/// screenshots — the server builds it with itemsWithScreenshots:NO attrList:NO),
/// so these cover just that graph:
///   LookinConnectionResponseAttachment.data -> LookinHierarchyInfo.displayItems
///     -> [LookinDisplayItem] -> LookinObject (oid, classChainList)
///
/// ponytail: only the fields get_hierarchy needs are decoded. backgroundColor
/// (an archived UIColor, absent on macOS) and the detail/attribute graph are
/// intentionally skipped here; add them with the 203 detail flow.

@objc(LKSResponseAttachment)
final class LKSResponseAttachment: NSObject, NSCoding {
    let data: Any?
    let dataTotalCount: Int
    let currentDataCount: Int
    let error: Any?

    required init?(coder: NSCoder) {
        // Superclass (LookinConnectionAttachment) encodes the payload under key "0".
        data = coder.decodeObject(forKey: "0")
        dataTotalCount = (coder.decodeObject(forKey: "dataTotalCount") as? NSNumber)?.intValue ?? 1
        currentDataCount = (coder.decodeObject(forKey: "currentDataCount") as? NSNumber)?.intValue ?? 1
        error = coder.decodeObject(forKey: "error")
    }
    func encode(with coder: NSCoder) {}
}

@objc(LKSHierarchyInfo)
final class LKSHierarchyInfo: NSObject, NSCoding {
    let displayItems: [LKSDisplayItem]

    required init?(coder: NSCoder) {
        // LookinHierarchyInfoCodingKey_DisplayItems == "1"
        displayItems = (coder.decodeObject(forKey: "1") as? [LKSDisplayItem]) ?? []
    }
    func encode(with coder: NSCoder) {}
}

@objc(LKSDisplayItem)
final class LKSDisplayItem: NSObject, NSCoding {
    let subitems: [LKSDisplayItem]
    let isHidden: Bool
    let alpha: Float
    let frame: CGRect
    let bounds: CGRect
    let viewObject: LKSObject?
    let layerObject: LKSObject?
    let hostViewControllerObject: LKSObject?
    let representedAsKeyWindow: Bool
    let customDisplayTitle: String?

    required init?(coder: NSCoder) {
        subitems = (coder.decodeObject(forKey: "subitems") as? [LKSDisplayItem]) ?? []
        isHidden = coder.decodeBool(forKey: "hidden")
        alpha = coder.decodeFloat(forKey: "alpha")
        // iOS encodes frame/bounds via encodeCGRect (compatible with decodeRect).
        frame = coder.decodeRect(forKey: "frame")
        bounds = coder.decodeRect(forKey: "bounds")
        viewObject = coder.decodeObject(forKey: "viewObject") as? LKSObject
        layerObject = coder.decodeObject(forKey: "layerObject") as? LKSObject
        hostViewControllerObject = coder.decodeObject(forKey: "hostViewControllerObject") as? LKSObject
        representedAsKeyWindow = coder.decodeBool(forKey: "representedAsKeyWindow")
        customDisplayTitle = coder.decodeObject(forKey: "customDisplayTitle") as? String
    }
    func encode(with coder: NSCoder) {}

    /// oid MUST be the layer's: screenshot(203) and attributes(210) both resolve
    /// the oid to a CALayer server-side. Every display item is built from a
    /// layer, so layerObject is always present.
    var oid: UInt64 { layerObject?.oid ?? viewObject?.oid ?? 0 }
    /// The view's oid, when a view backs this layer. Needed for modify_attribute
    /// with UIView setters (setAlpha:, setHidden:, ...) which don't exist on CALayer.
    var viewOid: UInt64? { viewObject?.oid }
    /// Prefer the view's class name for readability (e.g. "UILabel" over "CALayer").
    var lookinClassName: String { (viewObject ?? layerObject)?.lookinClassName ?? "?" }
}

@objc(LKSObject)
final class LKSObject: NSObject, NSCoding {
    let oid: UInt64
    let classChainList: [String]
    let memoryAddress: String?

    required init?(coder: NSCoder) {
        oid = (coder.decodeObject(forKey: "oid") as? NSNumber)?.uint64Value ?? 0
        classChainList = (coder.decodeObject(forKey: "classChainList") as? [String]) ?? []
        memoryAddress = coder.decodeObject(forKey: "memoryAddress") as? String
    }
    func encode(with coder: NSCoder) {}

    /// Most-derived class, e.g. "UILabel".
    var lookinClassName: String { classChainList.first ?? "?" }
}

/// Detail object returned by the HierarchyDetails(203) flow, one per requested
/// oid. Screenshots are encoded as PNG NSData (groupScreenshot.lookin_data);
/// attributes come as LookinAttributesGroup objects when attrRequest=Need.
@objc(LKSDisplayItemDetail)
final class LKSDisplayItemDetail: NSObject, NSCoding {
    let oid: UInt64
    let groupScreenshot: Data?
    let soloScreenshot: Data?
    let attributesGroupList: [LKSAttributesGroup]

    required init?(coder: NSCoder) {
        oid = (coder.decodeObject(forKey: "displayItemOid") as? NSNumber)?.uint64Value ?? 0
        groupScreenshot = coder.decodeObject(forKey: "groupScreenshot") as? Data
        soloScreenshot = coder.decodeObject(forKey: "soloScreenshot") as? Data
        attributesGroupList = (coder.decodeObject(forKey: "attributesGroupList") as? [LKSAttributesGroup]) ?? []
    }
    func encode(with coder: NSCoder) {}

    var screenshot: Data? { groupScreenshot ?? soloScreenshot }
}

@objc(LKSAttributesGroup)
final class LKSAttributesGroup: NSObject, NSCoding {
    let identifier: String?
    let userCustomTitle: String?
    let sections: [LKSAttributesSection]
    required init?(coder: NSCoder) {
        identifier = coder.decodeObject(forKey: "identifier") as? String
        userCustomTitle = coder.decodeObject(forKey: "userCustomTitle") as? String
        sections = (coder.decodeObject(forKey: "attrSections") as? [LKSAttributesSection]) ?? []
    }
    func encode(with coder: NSCoder) {}
}

@objc(LKSAttributesSection)
final class LKSAttributesSection: NSObject, NSCoding {
    let identifier: String?
    let attributes: [LKSAttribute]
    required init?(coder: NSCoder) {
        identifier = coder.decodeObject(forKey: "identifier") as? String
        attributes = (coder.decodeObject(forKey: "attributes") as? [LKSAttribute]) ?? []
    }
    func encode(with coder: NSCoder) {}
}

@objc(LKSAttribute)
final class LKSAttribute: NSObject, NSCoding {
    let identifier: String?
    let displayTitle: String?
    let attrType: Int
    let value: Any?
    required init?(coder: NSCoder) {
        identifier = coder.decodeObject(forKey: "identifier") as? String
        displayTitle = coder.decodeObject(forKey: "displayTitle") as? String
        attrType = coder.decodeInteger(forKey: "attrType")
        value = coder.decodeObject(forKey: "value")
    }
    func encode(with coder: NSCoder) {}
}

/// Stand-in for an archived iOS UIColor (absent on macOS). RGBA colors archive
/// as UIRed/UIGreen/UIBlue/UIAlpha; grayscale as UIWhite/UIAlpha.
@objc(LKSColor)
final class LKSColor: NSObject, NSCoding {
    let rgba: [Double]?
    required init?(coder: NSCoder) {
        func num(_ k: String) -> Double? { (coder.decodeObject(forKey: k) as? NSNumber)?.doubleValue }
        if let r = num("UIRed"), let g = num("UIGreen"), let b = num("UIBlue") {
            rgba = [r, g, b, num("UIAlpha") ?? 1]
        } else if let w = num("UIWhite") {
            rgba = [w, w, w, num("UIAlpha") ?? 1]
        } else {
            rgba = nil
        }
    }
    func encode(with coder: NSCoder) {}
}

enum LookinModel {
    /// Register every stand-in class so NSKeyedUnarchiver can instantiate them.
    static func register(on unarchiver: NSKeyedUnarchiver) {
        unarchiver.setClass(LKSResponseAttachment.self, forClassName: "LookinConnectionResponseAttachment")
        unarchiver.setClass(LKSHierarchyInfo.self, forClassName: "LookinHierarchyInfo")
        unarchiver.setClass(LKSDisplayItem.self, forClassName: "LookinDisplayItem")
        unarchiver.setClass(LKSObject.self, forClassName: "LookinObject")
        unarchiver.setClass(LKSDisplayItemDetail.self, forClassName: "LookinDisplayItemDetail")
        unarchiver.setClass(LKSAttributesGroup.self, forClassName: "LookinAttributesGroup")
        unarchiver.setClass(LKSAttributesSection.self, forClassName: "LookinAttributesSection")
        unarchiver.setClass(LKSAttribute.self, forClassName: "LookinAttribute")
        unarchiver.setClass(LKSColor.self, forClassName: "UIColor")
    }
}
