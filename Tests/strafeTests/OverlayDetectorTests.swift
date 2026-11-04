import Foundation
import XCTest
@testable import strafe

final class OverlayDetectorTests: XCTestCase {
    func testVisibleDockAndCmdTabAreNotOverlays() {
        for lists in [1, 2] {
            let wm = Element(children: [])
            let dock = Element(children: (0..<lists).map { _ in Element(role: .value("AXList")) })
            XCTAssertEqual(OverlaySnapshot.read(connections(wm, dock)), .inactive)
        }
    }

    func testMissionControlAndAppExposeInWindowManagerAreNative() {
        // Captured on macOS 27.2: both overlays use mc.display. No app or
        // window descendants need to be read, including on multiple displays.
        let overlay = Element(identifier: .value("mc.display"))
        let wm = Element(children: [overlay, overlay])
        let dock = Element(children: nil)
        XCTAssertEqual(OverlaySnapshot.read(connections(wm, dock)), .active)
        XCTAssertEqual(dock.calls, 0)
        XCTAssertEqual(overlay.childrenCalls, 0)
    }

    func testOlderDockHostedOverlayIdentifiersAreNative() {
        for identifier in ["mc", "appexpose"] {
            let dock = Element(children: [Element(identifier: .value(identifier))])
            XCTAssertEqual(OverlaySnapshot.read(connections(Element(children: []), dock)), .active)
        }
    }

    func testIncompleteUnsupportedAndNewLayoutsRemainNative() {
        let cases = [
            Element(children: nil),
            Element(children: [Element(identifier: .unavailable)]),
            Element(children: [Element(identifier: .value("unrecognized-overlay"))]),
            Element(children: [Element(role: .value("AXGroup"))]),
            Element(children: Array(repeating: Element(), count: OverlaySnapshot.childLimit + 1))
        ]
        for wm in cases {
            XCTAssertEqual(OverlaySnapshot.read(connections(wm, normalDock())), .unknown)
        }
        XCTAssertEqual(OverlaySnapshot.read([]), .unknown)
        XCTAssertEqual(OverlaySnapshot.read(connections(Element(children: []), Element(children: []))), .unknown)
    }

    func testOneBudgetIsSharedAcrossAllQueriesAndLateSuccessIsRejected() {
        let clock = Clock()
        let list = Element(role: .value("AXList"), clock: clock)
        let wm = Element(children: [], clock: clock)
        let dock = Element(children: [list], clock: clock)
        clock.cost = 0.001
        XCTAssertEqual(OverlaySnapshot.read(connections(wm, dock), now: { clock.time }), .inactive)
        XCTAssertEqual(clock.timeouts.count, 4)
        for (actual, expected) in zip(clock.timeouts, [0.005, 0.004, 0.003, 0.002]) {
            XCTAssertEqual(actual, expected, accuracy: 0.000001)
        }
        clock.time = 0
        clock.timeouts = []
        clock.cost = 0.002
        XCTAssertEqual(OverlaySnapshot.read(connections(wm, dock), now: { clock.time }), .unknown)
        // The identifier exhausted the total budget: role must not be queried.
        XCTAssertEqual(clock.timeouts.count, 3)
    }

    func testNoOverlayStateIsCachedBetweenSwipes() {
        let wm = Element(children: [])
        let hosts = connections(wm, normalDock())
        XCTAssertEqual(OverlaySnapshot.read(hosts), .inactive)
        wm.elements = [Element(identifier: .value("mc.display"))]
        XCTAssertEqual(OverlaySnapshot.read(hosts), .active)
        wm.elements = []
        XCTAssertEqual(OverlaySnapshot.read(hosts), .inactive)
    }

    func testPreparingConnectionsNeverBlocksGestureAndDoesNotPoll() {
        let preparation = Preparation(connections: connections(Element(children: []), normalDock()))
        preparation.block = true
        let detector = OverlayDetector(modern: true, observeLifecycle: false, prepare: { preparation.run() })
        detector.start()
        XCTAssertEqual(preparation.entered.wait(timeout: .now() + 1), .success)
        for _ in 0..<10 { XCTAssertEqual(detector.state(), .unknown) }
        XCTAssertEqual(preparation.count, 1)
        preparation.release.signal()
        waitForState(.inactive, detector)
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        XCTAssertEqual(preparation.count, 1)
        detector.stop()
        XCTAssertEqual(detector.state(), .unknown)
        XCTAssertEqual(preparation.count, 1)
    }

    func testStopInvalidatesInflightPreparation() {
        let preparation = Preparation(connections: connections(Element(children: []), normalDock()))
        preparation.block = true
        let detector = OverlayDetector(modern: true, observeLifecycle: false, prepare: { preparation.run() })
        detector.start()
        XCTAssertEqual(preparation.entered.wait(timeout: .now() + 1), .success)
        detector.stop()
        preparation.release.signal()
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        XCTAssertEqual(detector.state(), .unknown)
        detector.start()
        waitForState(.inactive, detector)
        XCTAssertEqual(preparation.count, 2)
        detector.stop()
    }

    func testProcessRestartImmediatelyInvalidatesOldConnection() {
        let preparation = Preparation(connections: connections(Element(children: []), normalDock()))
        let detector = OverlayDetector(modern: true, observeLifecycle: false, prepare: { preparation.run() })
        detector.start()
        waitForState(.inactive, detector)
        preparation.block = true
        detector.refresh()
        XCTAssertEqual(detector.state(), .unknown)
        preparation.release.signal()
        waitForState(.inactive, detector)
        XCTAssertEqual(preparation.count, 2)
        detector.stop()
    }

    private func normalDock() -> Element {
        Element(children: [Element(role: .value("AXList"))])
    }

    private func connections(_ wm: Element, _ dock: Element) -> [OverlayConnection] {
        [.init(host: .windowManager, root: wm), .init(host: .dock, root: dock)]
    }

    private func waitForState(_ state: OverlayState, _ detector: OverlayDetector,
                              file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            if detector.state() == state { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.001))
        }
        XCTFail("Detector did not reach \(state)", file: file, line: line)
    }
}

private final class Clock {
    var time = 0.0
    var cost = 0.0
    var timeouts: [Double] = []
}

private final class Element: OverlayElement {
    var elements: [Element]?
    let id: OverlayAttribute
    let roleValue: OverlayAttribute
    let clock: Clock?
    var calls = 0
    var childrenCalls = 0

    init(children: [Element]? = [], identifier: OverlayAttribute = .absent,
         role: OverlayAttribute = .absent, clock: Clock? = nil) {
        elements = children
        id = identifier
        roleValue = role
        self.clock = clock
    }

    private func called(_ timeout: TimeInterval) {
        calls += 1
        if let clock { clock.timeouts.append(timeout); clock.time += clock.cost }
    }

    func children(limit: Int, timeout: TimeInterval) -> [any OverlayElement]? {
        called(timeout)
        childrenCalls += 1
        return elements
    }
    func identifier(timeout: TimeInterval) -> OverlayAttribute { called(timeout); return id }
    func role(timeout: TimeInterval) -> OverlayAttribute { called(timeout); return roleValue }
}

private final class Preparation: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var shouldBlock = false
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let connections: [OverlayConnection]
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
    var block: Bool {
        get { lock.lock(); defer { lock.unlock() }; return shouldBlock }
        set { lock.lock(); shouldBlock = newValue; lock.unlock() }
    }
    init(connections: [OverlayConnection]) { self.connections = connections }
    func run() -> [OverlayConnection]? {
        lock.lock()
        calls += 1
        let blocked = shouldBlock
        shouldBlock = false
        lock.unlock()
        entered.signal()
        if blocked { _ = release.wait(timeout: .now() + 1) }
        return connections
    }
}
