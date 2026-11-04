import AppKit
import ApplicationServices
import CStrafe
import Foundation

enum OverlayState: String, Sendable {
    case inactive, active, unknown
}

enum OverlayHost: String, Sendable {
    case windowManager = "com.apple.WindowManager"
    case dock = "com.apple.dock"
}

enum OverlayAttribute: Equatable {
    case value(String), absent, unavailable
}

/// A narrow read-only seam. Implementations must honor each call's remaining
/// timeout. No application/window names, content, or descendant trees are read.
protocol OverlayElement: AnyObject {
    func children(limit: Int, timeout: TimeInterval) -> [any OverlayElement]?
    func identifier(timeout: TimeInterval) -> OverlayAttribute
    func role(timeout: TimeInterval) -> OverlayAttribute
    func subrole(timeout: TimeInterval) -> OverlayAttribute
}

struct OverlayConnection: @unchecked Sendable {
    let host: OverlayHost
    let root: any OverlayElement
}

enum OverlaySnapshot {
    static let budget: TimeInterval = 0.005
    static let childLimit = 16

    /// A positive, nonlocalized identity is required before taking a keyboard
    /// shortcut from the app switcher. Ordinary Dock lists have no subrole.
    static func appSwitcher(
        _ connections: [OverlayConnection],
        budget: TimeInterval = budget,
        now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) -> OverlayState {
        guard let dock = connections.first(where: { $0.host == .dock }) else { return .unknown }
        let deadline = now() + budget
        func remaining() -> TimeInterval { max(0, deadline - now()) }
        guard remaining() > 0,
              let children = dock.root.children(limit: childLimit, timeout: remaining()),
              !children.isEmpty, children.count <= childLimit,
              remaining() > 0 else { return .unknown }
        for child in children {
            guard remaining() > 0 else { return .unknown }
            let subrole = child.subrole(timeout: remaining())
            guard remaining() > 0 else { return .unknown }
            if subrole == .value("AXProcessSwitcherList") {
                let role = child.role(timeout: remaining())
                return remaining() > 0 && role == .value("AXList") ? .active : .unknown
            }
            if subrole == .unavailable { return .unknown }
        }
        return remaining() > 0 ? .inactive : .unknown
    }

    /// One deadline for the whole snapshot, not a fresh timeout per element.
    /// A late successful reply still cannot authorize interception. AX timeouts
    /// are OS messaging limits, not a hard realtime scheduling guarantee.
    static func read(
        _ connections: [OverlayConnection],
        budget: TimeInterval = budget,
        now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) -> OverlayState {
        guard !connections.isEmpty else { return .unknown }
        let deadline = now() + budget
        func remaining() -> TimeInterval { max(0, deadline - now()) }
        for connection in connections {
            guard remaining() > 0,
                  let children = connection.root.children(limit: childLimit, timeout: remaining()),
                  children.count <= childLimit,
                  remaining() > 0 else { return .unknown }
            // A healthy hidden Dock still exposes its application list. An
            // empty Dock snapshot can be initialization or a transition.
            if connection.host == .dock && children.isEmpty { return .unknown }
            for child in children {
                guard remaining() > 0 else { return .unknown }
                let identifier = child.identifier(timeout: remaining())
                guard remaining() > 0 else { return .unknown }
                switch (connection.host, identifier) {
                case (.windowManager, .value("mc.display")),
                     (.dock, .value("mc")), (.dock, .value("appexpose")):
                    return .active
                case (.dock, .absent):
                    // Normal Dock and Cmd–Tab expose one/two anonymous AXLists.
                    guard remaining() > 0,
                          child.role(timeout: remaining()) == .value("AXList"),
                          remaining() > 0 else { return .unknown }
                default:
                    // Never interpret an unsupported/new layout as evidence
                    // that there is no overlay.
                    return .unknown
                }
            }
        }
        return remaining() > 0 ? .inactive : .unknown
    }
}

private final class AXOverlayElement: OverlayElement {
    private let element: AXUIElement

    init(_ element: AXUIElement) { self.element = element }

    private func setTimeout(_ timeout: TimeInterval) -> Bool {
        timeout > 0 && AXUIElementSetMessagingTimeout(element, Float(timeout)) == .success
    }

    func children(limit: Int, timeout: TimeInterval) -> [any OverlayElement]? {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        guard setTimeout(timeout) else { return nil }
        var count = 0
        guard AXUIElementGetAttributeValueCount(element, kAXChildrenAttribute as CFString, &count) == .success,
              count >= 0, count <= limit,
              ProcessInfo.processInfo.systemUptime < deadline else { return nil }
        // CopyAttributeValues(index: 0) fails on WindowManager's empty array.
        if count == 0 { return [] }
        guard setTimeout(deadline - ProcessInfo.processInfo.systemUptime) else { return nil }
        var values: CFArray?
        // Fetch one extra element to distinguish a complete snapshot from a
        // truncated one without an unbounded AXChildren allocation/tree walk.
        guard AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString,
                                             0, limit + 1, &values) == .success,
              let values, CFArrayGetCount(values) == count,
              ProcessInfo.processInfo.systemUptime < deadline else { return nil }
        var result: [any OverlayElement] = []
        for value in values as [AnyObject] {
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            result.append(AXOverlayElement(value as! AXUIElement))
        }
        return result
    }

    func identifier(timeout: TimeInterval) -> OverlayAttribute {
        attribute(kAXIdentifierAttribute as CFString, timeout: timeout)
    }

    func role(timeout: TimeInterval) -> OverlayAttribute {
        attribute(kAXRoleAttribute as CFString, timeout: timeout)
    }

    func subrole(timeout: TimeInterval) -> OverlayAttribute {
        attribute(kAXSubroleAttribute as CFString, timeout: timeout)
    }

    private func attribute(_ name: CFString, timeout: TimeInterval) -> OverlayAttribute {
        guard setTimeout(timeout) else { return .unavailable }
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, name, &value) {
        case .success:
            guard let value = value as? String else { return .unavailable }
            return .value(value)
        case .noValue, .attributeUnsupported: return .absent
        default: return .unavailable
        }
    }
}

/// Caches *connections*, never overlay state. Preparation happens off the tap;
/// fresh bounded snapshots happen only at horizontal gesture beginnings or
/// candidate Control–Command–Arrow shortcuts.
/// There is no timer or AX notification subscription. macOS 27.2 moves the
/// overlays to WindowManager and does not send the old Dock Exposé notifications.
final class OverlayDetector: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.tatoalo.strafe.overlay-setup", qos: .userInitiated)
    private let prepare: @Sendable () -> [OverlayConnection]?
    private let modern: Bool
    private let observeLifecycle: Bool
    private var running = false
    private var generation: UInt64 = 0
    private var preparing: UInt64?
    private var connections: [OverlayConnection]?
    private var observers: [any NSObjectProtocol] = []
    private let diagnostics = ProcessInfo.processInfo.environment["STRAFE_OVERLAY_DIAGNOSTICS"] == "1"
    private var diagnosticBudget = 64 // accessed only by the event-tap thread

    init(
        modern: Bool = strafe_uses_iohid_payload(),
        observeLifecycle: Bool = true,
        prepare: (@Sendable () -> [OverlayConnection]?)? = nil
    ) {
        self.modern = modern
        self.observeLifecycle = observeLifecycle
        self.prepare = prepare ?? { OverlayDetector.prepareConnections(modern: modern) }
    }

    /// Lifecycle methods run on the tap's main thread. The lock protects only
    /// publication against background preparation, never a remote AX request.
    func start() {
        lock.lock()
        guard !running else { lock.unlock(); return }
        running = true
        lock.unlock()
        if observeLifecycle {
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                          let id = app.bundleIdentifier, OverlayHost(rawValue: id) != nil else { return }
                    self?.refresh()
                })
            }
            observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
        refresh()
    }

    func stop() {
        lock.lock()
        running = false
        generation &+= 1
        connections = nil
        preparing = nil
        lock.unlock()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }

    deinit { stop() }

    /// Invalidate immediately on process changes. An older preparation job
    /// cannot publish over a newer connection or revive a stopped detector.
    func refresh() {
        lock.lock()
        generation &+= 1
        connections = nil
        preparing = nil
        lock.unlock()
        requestPreparation()
    }

    private func requestPreparation() {
        lock.lock()
        guard running, preparing == nil else { lock.unlock(); return }
        let token = generation
        preparing = token
        lock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            let prepared = self.prepare()
            self.lock.lock()
            if self.running && self.generation == token {
                self.connections = prepared
                self.preparing = nil
            }
            self.lock.unlock()
        }
    }

    func state() -> OverlayState {
        guard modern else { return strafe_is_expose_active() ? .active : .inactive }
        return query(kind: "overlay", read: { OverlaySnapshot.read($0) })
    }

    func appSwitcherState() -> OverlayState {
        query(kind: "app-switcher", read: { OverlaySnapshot.appSwitcher($0) })
    }

    private func query(kind: String, read: ([OverlayConnection]) -> OverlayState) -> OverlayState {
        let start = ProcessInfo.processInfo.systemUptime
        lock.lock()
        let snapshot = running ? connections : nil
        let token = generation
        lock.unlock()
        var state = snapshot.map(read) ?? .unknown
        lock.lock()
        if !running || generation != token { state = .unknown }
        lock.unlock()
        if state == .unknown {
            // Retry warming only in response to this user gesture, never on a
            // periodic retry timer. Preserve the current whole native gesture.
            requestPreparation()
        }
        if diagnostics && diagnosticBudget > 0 {
            diagnosticBudget -= 1
            let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
            let reportedState = state
            queue.async {
                FileHandle.standardError.write(Data("[OverlayDetector] kind=\(kind) state=\(reportedState.rawValue) elapsed_ms=\(elapsed)\n".utf8))
            }
        }
        return state
    }

    private static func prepareConnections(modern: Bool) -> [OverlayConnection]? {
        guard AXIsProcessTrusted() else { return nil }
        var result: [OverlayConnection] = []
        // WindowManager first: a confirmed overlay needs no Dock round-trip.
        let hosts: [OverlayHost] = modern ? [.windowManager, .dock] : [.dock]
        for host in hosts {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: host.rawValue).first else {
                return nil
            }
            let root = AXOverlayElement(AXUIElementCreateApplication(app.processIdentifier))
            // Cold AX connections can cost tens of milliseconds. Warm each
            // independently, even when the other host currently has an overlay.
            guard root.children(limit: OverlaySnapshot.childLimit, timeout: 0.1) != nil else { return nil }
            result.append(OverlayConnection(host: host, root: root))
        }
        return result
    }

    /// Headless, read-only CLI diagnostic. Cold preparation may block here;
    /// unlike the resident event tap, the CLI has no input stream to hold up.
    static func diagnosticSnapshot() -> (state: OverlayState, milliseconds: Double) {
        let connections = strafe_uses_iohid_payload() ? prepareConnections(modern: true) : nil
        let start = ProcessInfo.processInfo.systemUptime
        let state: OverlayState
        if strafe_uses_iohid_payload() {
            state = connections.map { OverlaySnapshot.read($0) } ?? .unknown
        } else {
            state = strafe_is_expose_active() ? .active : .inactive
        }
        return (state, (ProcessInfo.processInfo.systemUptime - start) * 1000)
    }
}
