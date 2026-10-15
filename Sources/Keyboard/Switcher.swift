// F19(= Caps Lock) 누름을 가로채 바로 한영 전환하고, 길게 누르면 영문 대문자로 바꾼다.
import AppKit

private let longPressDelay: TimeInterval = 0.5
// 누름과 뗌이 1ms쯤 붙어 있으면 macOS 26이 단축키로 받지 않는다. 30ms면 매번 받고, 키를 떼기 전에 전환된다.
private let pulseGap: TimeInterval = 0.03

var capsLockOn: Bool { CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift) }

func setCapsLock(_ enabled: Bool) {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
    guard service != IO_OBJECT_NULL else { return }
    defer { IOObjectRelease(service) }
    var connection: io_connect_t = 0
    guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection) == KERN_SUCCESS else { return }
    defer { IOServiceClose(connection) }
    IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), enabled)
}

final class Switcher {
    // 우리가 보낸 이벤트를 다시 처리하지 않도록 표시하는 값.
    private let marker = Int64.random(in: 1...Int64.max)
    private var tap: CFMachPort?
    private var pressEvent: CGEvent?
    private var longPressTimer: DispatchWorkItem?
    private var capsBeforePress = false
    private var pendingCaps: Bool?
    private var capsGeneration = 0

    var isRunning: Bool { tap != nil }
    var enabled = true {
        didSet { if let tap { CGEvent.tapEnable(tap: tap, enable: enabled) } }
    }

    // 손쉬운 사용 권한이 있어야 만들어진다. 없으면 false.
    @discardableResult
    func start() -> Bool {
        guard tap == nil, AXIsProcessTrusted() else { return tap != nil }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, info in
                let switcher = Unmanaged<Switcher>.fromOpaque(info!).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = switcher.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                return switcher.handle(type, event) ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: enabled)
        return true
    }

    // 입력 소스가 바뀌면 호출. 길게 눌러 영문으로 가는 중이었다면 Caps Lock을 마저 바꾼다.
    func inputSourceChanged() {
        if pendingCaps != nil && InputSource.isEnglish { finishCaps() }
    }

    // F19의 실제 누름/뗌은 삼키고, 누르는 순간 우리가 만든 누름+뗌 한 쌍을 보낸다.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard enabled, event.getIntegerValueField(.keyboardEventKeycode) == f19KeyCode,
              event.getIntegerValueField(.eventSourceUserData) != marker else { return false }
        if type == .keyDown {
            // 반복이 아닌 누름은 항상 새 누름으로 받는다. 뗌을 놓쳐 이전 누름이 남아 있어도 여기서 정리된다.
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                longPressTimer?.cancel()
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

    private func postSwitch(from event: CGEvent) {
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
    private func longPress() {
        longPressTimer = nil
        guard let event = pressEvent else { return }
        pendingCaps = !capsBeforePress
        capsGeneration += 1
        let generation = capsGeneration
        if InputSource.isEnglish { finishCaps() } else { postSwitch(from: event) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if self?.capsGeneration == generation { self?.pendingCaps = nil }
        }
    }

    private func finishCaps() {
        guard let desired = pendingCaps else { return }
        pendingCaps = nil
        setCapsLock(desired)
        // 입력기 전환 직후 Caps Lock이 되돌려지는 경우가 있어 한 번 더 맞춘다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { if capsLockOn != desired && InputSource.isEnglish { setCapsLock(desired) } }
    }
}
