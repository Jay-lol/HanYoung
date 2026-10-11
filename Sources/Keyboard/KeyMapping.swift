// Caps Lock을 F19로 바꾸는 HID 매핑과, F19를 "이전 입력 소스 선택"에 거는 시스템 단축키.
import AppKit

let capsLockUsage: UInt64 = 0x700000039
let f19Usage: UInt64 = 0x70000006e
let f19KeyCode: Int64 = 80

private let srcKey = "HIDKeyboardModifierMappingSrc", dstKey = "HIDKeyboardModifierMappingDst"
private typealias Mapping = [String: NSNumber]

enum KeyMapping {
    // 모든 키보드에 Caps Lock → F19를 걸거나 우리 매핑만 뺀다. 다른 매핑은 그대로 둔다.
    static func apply(_ enabled: Bool) {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        let services = (IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? [])
            .filter { IOHIDServiceClientConformsTo($0, 1, 6) != 0 }
        let ours: Mapping = [srcKey: NSNumber(value: capsLockUsage), dstKey: NSNumber(value: f19Usage)]
        for service in services {
            let current = IOHIDServiceClientCopyProperty(service, "UserKeyMapping" as CFString) as? [Mapping] ?? []
            var next = enabled ? current.filter { $0[srcKey]?.uint64Value != capsLockUsage } : current.filter { $0 != ours }
            if enabled { next.append(ours) }
            if next != current { IOHIDServiceClientSetProperty(service, "UserKeyMapping" as CFString, next as CFArray) }
        }
    }

    // 시스템 설정 > 키보드 단축키 > 입력 소스 > "이전 입력 소스 선택"(ID 60)을 fn+F19로.
    // F19 이벤트에는 fn 플래그가 붙어 와서, 수식키 없이 등록하면 영어→한글 전환이 먹지 않는다.
    static func setSwitchShortcut() {
        let domain = "com.apple.symbolichotkeys" as CFString, key = "AppleSymbolicHotKeys" as CFString
        CFPreferencesAppSynchronize(domain)
        var keys = CFPreferencesCopyAppValue(key, domain) as? [String: Any] ?? [:]
        let wanted: [String: Any] = ["enabled": true, "value": ["type": "standard", "parameters": [65535, Int(f19KeyCode), Int(CGEventFlags.maskSecondaryFn.rawValue)]]]
        if let current = keys["60"] as? NSDictionary, current.isEqual(to: wanted) { return }
        keys["60"] = wanted
        CFPreferencesSetAppValue(key, keys as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")
        process.arguments = ["-u", "-virtualSession"]
        try? process.run(); process.waitUntilExit()
    }
}
