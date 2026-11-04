import CoreGraphics
import Foundation

/// BetterMouse retains a physically held Command modifier on its Control–Arrow
/// shortcuts. Carbon's Control–Arrow registration does not match that chord.
/// Claim it only while Dock positively exposes AXProcessSwitcherList. No key
/// text is read, and ordinary keys do no AX work, preference reads, or locking.
/// Like SwipeInterceptor, all mutable state is confined to the tap's main loop.
final class AppSwitcherShortcuts: @unchecked Sendable {
    private let engine: SwitchEngine
    private let enabled: () -> Bool
    private let switcherState: () -> OverlayState
    private var leftOwner: Int64?
    private var rightOwner: Int64?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var commandHeld = false

    init(engine: SwitchEngine, enabled: @escaping () -> Bool,
         switcherState: @escaping () -> OverlayState) {
        self.engine = engine
        self.enabled = enabled
        self.switcherState = switcherState
    }

    /// Prepare once, but keep the keyboard tap disabled outside Command holds.
    /// The gesture tap forwards modifier changes; ordinary typing never has to
    /// round-trip through this active keyboard tap. No polling is involved.
    func start() {
        guard eventTap == nil else { return }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let handler = Unmanaged<AppSwitcherShortcuts>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    handler.reset()
                    handler.resyncModifiers()
                    return Unmanaged.passUnretained(event)
                }
                return handler.consumes(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            FileHandle.standardError.write(Data("[AppSwitcherShortcuts] could not create keyboard tap\n".utf8))
            return
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        eventTap = tap
        runLoopSource = source
        resyncModifiers()
    }

    func stop() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        commandHeld = false
        reset()
    }

    func modifiersChanged(_ flags: CGEventFlags) {
        let held = flags.contains(.maskCommand)
        guard held != commandHeld else { return }
        commandHeld = held
        if !held { reset() }
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: held) }
    }

    func resyncModifiers() {
        commandHeld = CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand)
        if !commandHeld { reset() }
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: commandHeld) }
    }

    func reset() {
        leftOwner = nil
        rightOwner = nil
    }

    /// True means this event belongs to a shortcut we have claimed.
    func consumes(type: CGEventType, event: CGEvent) -> Bool {
        guard type == .keyDown || type == .keyUp else { return false }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        guard key == 123 || key == 124 else { return false }
        let pid = event.getIntegerValueField(.eventSourceUnixProcessID)
        let owner = key == 123 ? leftOwner : rightOwner
        if type == .keyUp {
            guard owner == pid else { return false }
            if key == 123 { leftOwner = nil } else { rightOwner = nil }
            return true
        }
        // Finish a claimed press even if the overlay closes. A repeated down
        // must not fire again or re-query AX. Releasing Command disables this
        // tap and discards pending ownership, including a lost key-up.
        if owner == pid { return true }
        guard owner == nil,
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return false }
        let relevant: CGEventFlags = [.maskControl, .maskCommand, .maskShift, .maskAlternate]
        let chord: CGEventFlags = [.maskControl, .maskCommand]
        guard event.flags.intersection(relevant) == chord,
              enabled(), switcherState() == .active else { return false }

        if key == 123 { leftOwner = pid } else { rightOwner = pid }
        do {
            try engine.switchSpace(key == 123 ? .left : .right)
        } catch SwitchEngineError.atEdge {
            // At a desktop edge, do not let this become switcher navigation.
        } catch {
            FileHandle.standardError.write(Data("[AppSwitcherShortcuts] switch failed: \(error)\n".utf8))
        }
        return true
    }
}
