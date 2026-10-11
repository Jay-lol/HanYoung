// HanYoung: Caps Lock 한영 전환 메뉴바 앱.
// 1) Caps Lock을 F19로 매핑  2) "이전 입력 소스 선택" 단축키를 F19로  3) F19 누르는 즉시 전환 이벤트 발생
// 길게 누르면(0.5초) 영문으로 돌아가 Caps Lock을 토글한다.
import AppKit
import Carbon
import ServiceManagement

let capsLockUsage: UInt64 = 0x700000039
let f19Usage: UInt64 = 0x70000006e
let f19KeyCode: Int64 = 80
let longPressDelay: TimeInterval = 0.5
// 누름과 뗌이 1ms쯤 붙어 있으면 macOS 26이 단축키로 받지 않는다. 30ms면 매번 받고, 키를 떼기 전에 전환된다.
let pulseGap: TimeInterval = 0.03
let srcKey = "HIDKeyboardModifierMappingSrc", dstKey = "HIDKeyboardModifierMappingDst"
typealias Mapping = [String: NSNumber]


// 모든 키보드에 Caps Lock → F19를 걸거나 우리 매핑만 뺀다. 다른 매핑은 그대로 둔다.
func applyMapping(_ enabled: Bool) {
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
func setSwitchShortcut() {
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

func setCapsLock(_ enabled: Bool) {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
    guard service != IO_OBJECT_NULL else { return }
    defer { IOObjectRelease(service) }
    var connection: io_connect_t = 0
    guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection) == KERN_SUCCESS else { return }
    defer { IOServiceClose(connection) }
    IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), enabled)
}

var capsLockOn: Bool { CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift) }

func language(_ source: TISInputSource) -> String {
    guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return "" }
    return (Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String])?.first ?? ""
}
var currentLanguage: String { TISCopyCurrentKeyboardInputSource().map { language($0.takeRetainedValue()) } ?? "" }
var isEnglish: Bool { currentLanguage.hasPrefix("en") }

// 메뉴의 한국어/영어 선택. 단축키가 아니라 입력 소스를 직접 고른다.
func selectLanguage(_ prefix: String) {
    let filter = [kTISPropertyInputSourceIsEnabled as String: true, kTISPropertyInputSourceIsSelectCapable as String: true,
                  kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String] as CFDictionary
    let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] ?? []
    if let source = sources.first(where: { language($0).hasPrefix(prefix) }) { TISSelectInputSource(source) }
}

// KO/EN 배지. 한국어는 채운 배지, 영어는 테두리 배지.
func badgeImage(_ label: String, filled: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: 22, height: 20), flipped: false) { rect in
        let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 1.25), xRadius: 3, yRadius: 3)
        NSColor.black.set()
        if filled { shape.fill() } else { shape.lineWidth = 0.8; shape.stroke() }
        let text = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: NSColor.black])
        let size = text.size()
        let origin = NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2)
        if filled {
            let mask = NSImage(size: rect.size, flipped: false) { _ in text.draw(at: origin); return true }
            mask.draw(in: rect, from: .zero, operation: .destinationOut, fraction: 1)
        } else { text.draw(at: origin) }
        return true
    }
    image.isTemplate = true
    return image
}
let koreanBadge = badgeImage("KO", filled: true), englishBadge = badgeImage("EN", filled: false)

// macOS 기본 입력기 메뉴바 아이콘(com.apple.TextInputMenu의 visible). 원래 값을 저장해두고 숨기며, 종료 시 되돌린다.
func setSystemInputMenu(_ value: CFPropertyList?) {
    let domain = "com.apple.TextInputMenu" as CFString
    CFPreferencesSetAppValue("visible" as CFString, value, domain)
    CFPreferencesAppSynchronize(domain)
    // launchd가 바로 다시 띄우는 에이전트라, 재시작해서 설정을 다시 읽게 한다.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    process.arguments = ["TextInputMenuAgent"]
    process.standardError = FileHandle.nullDevice
    try? process.run(); process.waitUntilExit()
}
func hideSystemInputMenu() {
    let defaults = UserDefaults.standard, domain = "com.apple.TextInputMenu" as CFString
    CFPreferencesAppSynchronize(domain)
    let current = CFPreferencesCopyAppValue("visible" as CFString, domain)
    if !defaults.bool(forKey: "inputMenuBackedUp") {
        defaults.set(current, forKey: "originalInputMenu")
        defaults.set(true, forKey: "inputMenuBackedUp")
    }
    if (current as? NSNumber)?.boolValue != false { setSystemInputMenu(kCFBooleanFalse) }
}
func restoreSystemInputMenu() {
    let defaults = UserDefaults.standard
    guard defaults.bool(forKey: "inputMenuBackedUp") else { return }
    setSystemInputMenu(defaults.object(forKey: "originalInputMenu") as CFPropertyList?)
    defaults.removeObject(forKey: "originalInputMenu")
    defaults.removeObject(forKey: "inputMenuBackedUp")
}

final class App: NSObject, NSApplicationDelegate {
    let marker = Int64.random(in: 1...Int64.max)
    var tap: CFMachPort?
    var statusItem: NSStatusItem!
    var paused = false
    var pressEvent: CGEvent?
    var longPressTimer: DispatchWorkItem?
    var capsBeforePress = false
    var pendingCaps: Bool?
    var capsGeneration = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: 28)
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self
        statusItem.button?.appearsDisabled = true  // 키 감시가 시작되면 켜진다
        updateIcon()
        hideSystemInputMenu()
        setSwitchShortcut()
        applyMapping(true)
        // 새로 연결한 키보드나 재연결로 매핑이 풀린 키보드에 다시 건다. 권한이 나중에 허용되면 그때 키 감시를 시작한다.
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, !self.paused else { return }
            applyMapping(true)
            if self.tap == nil { self.startTap() }
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(inputSourceChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
        if !AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) { return }
        startTap()
    }

    func applicationWillTerminate(_ notification: Notification) { applyMapping(false); restoreSystemInputMenu() }

    func updateIcon() {
        let korean = currentLanguage.hasPrefix("ko")
        statusItem.button?.image = korean ? koreanBadge : englishBadge
        statusItem.button?.toolTip = "HanYoung · 현재 입력: \(korean ? "한국어" : "영어")"
    }

    func startTap() {
        guard AXIsProcessTrusted() else { return }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, info in
                let app = Unmanaged<App>.fromOpaque(info!).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = app.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                return app.handle(type, event) ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        statusItem.button?.appearsDisabled = false
    }

    // F19의 실제 누름/뗌은 삼키고, 누르는 순간 우리가 만든 누름+뗌 한 쌍을 보낸다.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard !paused, event.getIntegerValueField(.keyboardEventKeycode) == f19KeyCode,
              event.getIntegerValueField(.eventSourceUserData) != marker else { return false }
        if type == .keyDown {
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 && pressEvent == nil {
                pressEvent = event.copy()
                capsBeforePress = capsLockOn
                postSwitch(from: event)
                let task = DispatchWorkItem { [weak self] in self?.longPress() }
                longPressTimer = task
                DispatchQueue.main.asyncAfter(deadline: .now() + longPressDelay, execute: task)
            }
        } else {
            longPressTimer?.cancel(); longPressTimer = nil
            pressEvent = nil
        }
        return true
    }

    func postSwitch(from event: CGEvent) {
        guard let down = event.copy(), let up = event.copy() else { return }
        down.type = .keyDown; up.type = .keyUp
        // F키 식별 플래그만 남기고, Caps Lock은 지금 상태로 맞춘다.
        let flags = event.flags.intersection([.maskSecondaryFn, .maskNumericPad]).union(capsLockOn ? .maskAlphaShift : [])
        for pulse in [down, up] {
            pulse.flags = flags
            pulse.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            pulse.setIntegerValueField(.eventSourceUserData, value: marker)
        }
        down.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + pulseGap) { up.post(tap: .cghidEventTap) }
    }

    // 길게 누름: 방금 전환을 되돌려 영문으로 가고, 도착하면 Caps Lock을 누르기 전 반대로.
    func longPress() {
        longPressTimer = nil
        guard let event = pressEvent else { return }
        pendingCaps = !capsBeforePress
        capsGeneration += 1
        let generation = capsGeneration
        if isEnglish { finishCaps() } else { postSwitch(from: event) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if self?.capsGeneration == generation { self?.pendingCaps = nil }
        }
    }

    @objc func inputSourceChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.updateIcon()
            if self?.pendingCaps != nil && isEnglish { self?.finishCaps() }
        }
    }

    func finishCaps() {
        guard let desired = pendingCaps else { return }
        pendingCaps = nil
        setCapsLock(desired)
        // 입력기 전환 직후 Caps Lock이 되돌려지는 경우가 있어 한 번 더 맞춘다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { if capsLockOn != desired && isEnglish { setCapsLock(desired) } }
    }

    @objc func togglePause() {
        paused.toggle()
        applyMapping(!paused)
        if let tap { CGEvent.tapEnable(tap: tap, enable: !paused) }
        statusItem.button?.appearsDisabled = paused
    }

    @objc func toggleLogin() {
        let service = SMAppService.mainApp
        try? service.status == .enabled ? service.unregister() : service.register()
    }

    @objc func selectKorean() { selectLanguage("ko") }
    @objc func selectEnglish() { selectLanguage("en") }

    @objc func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

extension App: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        let brand = menu.addItem(withTitle: "HanYoung", action: nil, keyEquivalent: "")
        brand.attributedTitle = NSAttributedString(string: "HanYoung", attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .heavy), .kern: 0.6])
        if tap == nil {
            menu.addItem(withTitle: "⚠️ 손쉬운 사용 권한 필요 — 허용하기…", action: #selector(openAccessibility), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        let language = currentLanguage
        let korean = menu.addItem(withTitle: "한국어", action: #selector(selectKorean), keyEquivalent: "")
        korean.target = self; korean.image = koreanBadge; korean.state = language.hasPrefix("ko") ? .on : .off
        let english = menu.addItem(withTitle: "영어", action: #selector(selectEnglish), keyEquivalent: "")
        english.target = self; english.image = englishBadge; english.state = language.hasPrefix("en") ? .on : .off
        menu.addItem(.separator())
        let enabled = menu.addItem(withTitle: "활성화", action: #selector(togglePause), keyEquivalent: "")
        enabled.target = self; enabled.state = paused ? .off : .on
        let login = menu.addItem(withTitle: "로그인 시 시작", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
