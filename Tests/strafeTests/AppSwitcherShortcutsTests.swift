import CoreGraphics
import XCTest
@testable import strafe

final class AppSwitcherShortcutsTests: XCTestCase {
    func testMouseAndKeyboardChordsSwitchOnlyWithConfirmedSwitcher() {
        for pid: Int64 in [0, 79464] {
            for key: Int64 in [123, 124] {
                let engine = ShortcutEngine()
                let handler = AppSwitcherShortcuts(engine: engine, enabled: { true }, switcherState: { .active })
                XCTAssertTrue(handler.consumes(type: .keyDown, event: event(key, pid: pid)))
                XCTAssertTrue(handler.consumes(type: .keyUp, event: event(key, pid: pid, flags: [])))
                XCTAssertEqual(engine.directions, [key == 123 ? .left : .right])
            }
        }
    }

    func testNormalAppsAndUnknownStatePassThroughUnchanged() {
        for state in [OverlayState.inactive, .unknown] {
            let engine = ShortcutEngine()
            let handler = AppSwitcherShortcuts(engine: engine, enabled: { true }, switcherState: { state })
            let sample = event(123)
            XCTAssertFalse(handler.consumes(type: .keyDown, event: sample))
            XCTAssertFalse(handler.consumes(type: .keyUp, event: sample))
            XCTAssertEqual(sample.flags, [.maskControl, .maskCommand])
            XCTAssertTrue(engine.directions.isEmpty)
        }
    }

    func testOtherKeysAndModifiersNeverReadSettingsOrAX() {
        let handler = AppSwitcherShortcuts(engine: ShortcutEngine(), enabled: {
            XCTFail("Non-candidate read preferences")
            return true
        }, switcherState: {
            XCTFail("Non-candidate read Accessibility")
            return .active
        })
        for key: Int64 in [0, 48, 49, 53, 126] {
            XCTAssertFalse(handler.consumes(type: .keyDown, event: event(key)))
            XCTAssertFalse(handler.consumes(type: .keyUp, event: event(key)))
        }
        for flags: CGEventFlags in [[], .maskControl, .maskCommand,
                                    [.maskCommand, .maskControl, .maskShift],
                                    [.maskCommand, .maskControl, .maskAlternate]] {
            XCTAssertFalse(handler.consumes(type: .keyDown, event: event(123, flags: flags)))
        }
        XCTAssertFalse(handler.consumes(type: .flagsChanged, event: event(123)))
    }

    func testDisabledHotkeysNeverQueryOrConsume() {
        let engine = ShortcutEngine()
        let handler = AppSwitcherShortcuts(engine: engine, enabled: { false }, switcherState: {
            XCTFail("Disabled hotkeys queried AX")
            return .active
        })
        XCTAssertFalse(handler.consumes(type: .keyDown, event: event(123)))
        XCTAssertFalse(handler.consumes(type: .keyUp, event: event(123)))
        XCTAssertTrue(engine.directions.isEmpty)
    }

    func testClaimedPressDoesNotRepeatOrConsumeAnotherSourcesRelease() {
        let engine = ShortcutEngine()
        var checks = 0
        let handler = AppSwitcherShortcuts(engine: engine, enabled: { true }, switcherState: {
            checks += 1
            return checks == 1 ? .active : .inactive
        })
        let down = event(123)
        XCTAssertTrue(handler.consumes(type: .keyDown, event: down))
        XCTAssertTrue(handler.consumes(type: .keyDown, event: down))
        down.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        XCTAssertTrue(handler.consumes(type: .keyDown, event: down))
        XCTAssertFalse(handler.consumes(type: .keyUp, event: event(123, pid: 42)))
        XCTAssertTrue(handler.consumes(type: .keyUp, event: event(123)))
        XCTAssertFalse(handler.consumes(type: .keyDown, event: event(123)))
        XCTAssertEqual(checks, 2)
        XCTAssertEqual(engine.directions, [.left])
    }

    func testRepeatThatStartedElsewhereIsNeverClaimed() {
        let handler = AppSwitcherShortcuts(engine: ShortcutEngine(), enabled: { true }, switcherState: {
            XCTFail("A repeated press must not be claimed partway through")
            return .active
        })
        let repeatEvent = event(123)
        repeatEvent.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        XCTAssertFalse(handler.consumes(type: .keyDown, event: repeatEvent))
    }

    func testReleasingCommandClearsAClaimWithMissingKeyUp() {
        let engine = ShortcutEngine()
        let handler = AppSwitcherShortcuts(engine: engine, enabled: { true }, switcherState: { .active })
        handler.modifiersChanged(.maskCommand)
        XCTAssertTrue(handler.consumes(type: .keyDown, event: event(123)))
        handler.modifiersChanged([])
        XCTAssertFalse(handler.consumes(type: .keyUp, event: event(123)))
        handler.modifiersChanged(.maskCommand)
        XCTAssertTrue(handler.consumes(type: .keyDown, event: event(123)))
        XCTAssertEqual(engine.directions, [.left, .left])
    }

    func testDesktopEdgeDoesNotBecomeAppSwitcherNavigation() {
        let engine = ShortcutEngine()
        engine.atEdge = true
        let handler = AppSwitcherShortcuts(engine: engine, enabled: { true }, switcherState: { .active })
        XCTAssertTrue(handler.consumes(type: .keyDown, event: event(124)))
        XCTAssertTrue(handler.consumes(type: .keyUp, event: event(124)))
        engine.atEdge = false
        XCTAssertTrue(handler.consumes(type: .keyDown, event: event(123)))
        XCTAssertEqual(engine.directions, [.right, .left])
    }

    func testMouseCleanupAndSystemReconciliationKeepPhysicallyHeldCommand() {
        let handler = repairHandler()
        handler.modifiersChanged(.maskCommand)
        XCTAssertTrue(handler.consumes(type: .keyDown, event: event(123)))
        XCTAssertTrue(handler.consumes(type: .keyUp, event: event(123)))
        let cleanup = modifier(59, flags: .maskShift)
        handler.handleModifier(cleanup)
        XCTAssertEqual(cleanup.flags, [.maskCommand, .maskShift])
        let reconciliation = modifier(0, pid: 0)
        handler.handleModifier(reconciliation)
        XCTAssertEqual(reconciliation.flags, .maskCommand)
    }

    func testUnclaimedShortcutNeverRepairsModifiers() {
        for state in [OverlayState.inactive, .unknown] {
            let handler = AppSwitcherShortcuts(engine: ShortcutEngine(), enabled: { true }, switcherState: { state }, commandIsPhysicallyHeld: {
                XCTFail("Unclaimed shortcut inspected physical modifiers")
                return true
            })
            XCTAssertFalse(handler.consumes(type: .keyDown, event: event(123)))
            let cleanup = modifier(59)
            handler.handleModifier(cleanup)
            XCTAssertEqual(cleanup.flags, [])
        }
    }

    func testUnrelatedModifierSourcesAndKeysStayUntouched() {
        for (pid, key): (Int64, Int64) in [(42, 59), (42, 0), (79464, 55), (0, 55)] {
            let handler = repairHandler()
            XCTAssertTrue(handler.consumes(type: .keyDown, event: event(123)))
            let unrelated = modifier(key, pid: pid)
            handler.handleModifier(unrelated)
            XCTAssertEqual(unrelated.flags, [])
        }
    }

    func testModifierRepairExpiresWithoutSchedulingWork() {
        var time = 0.0
        let handler = AppSwitcherShortcuts(engine: ShortcutEngine(), enabled: { true }, switcherState: { .active }, commandIsPhysicallyHeld: {
            XCTFail("Expired repair inspected physical modifiers")
            return true
        }, now: { time })
        XCTAssertTrue(handler.consumes(type: .keyDown, event: event(123)))
        time = 0.251
        let cleanup = modifier(59)
        handler.handleModifier(cleanup)
        XCTAssertEqual(cleanup.flags, [])
    }

    func testModifierRepairNeverKeepsReleasedPhysicalCommandDown() {
        let handler = repairHandler(physicallyHeld: false)
        XCTAssertTrue(handler.consumes(type: .keyDown, event: event(123)))
        let cleanup = modifier(59)
        handler.handleModifier(cleanup)
        XCTAssertEqual(cleanup.flags, [])
    }

    func testPhysicalShortcutsAndResetDoNotLeaveRepairScope() {
        for pid: Int64 in [0, 79464] {
            let handler = repairHandler()
            XCTAssertTrue(handler.consumes(type: .keyDown, event: event(123, pid: pid)))
            if pid != 0 { handler.reset() }
            let cleanup = modifier(0, pid: 0)
            handler.handleModifier(cleanup)
            XCTAssertEqual(cleanup.flags, [])
        }
    }

    func testNextUnclaimedShortcutEndsPreviousCleanupScope() {
        var state = OverlayState.active
        let handler = AppSwitcherShortcuts(engine: ShortcutEngine(), enabled: { true }, switcherState: { state }, commandIsPhysicallyHeld: { true })
        XCTAssertTrue(handler.consumes(type: .keyDown, event: event(123)))
        XCTAssertTrue(handler.consumes(type: .keyUp, event: event(123)))
        state = .inactive
        XCTAssertFalse(handler.consumes(type: .keyDown, event: event(123)))
        let cleanup = modifier(59)
        handler.handleModifier(cleanup)
        XCTAssertEqual(cleanup.flags, [])
    }

    private func repairHandler(physicallyHeld: Bool = true) -> AppSwitcherShortcuts {
        AppSwitcherShortcuts(engine: ShortcutEngine(), enabled: { true }, switcherState: { .active }, commandIsPhysicallyHeld: { physicallyHeld })
    }

    private func modifier(_ key: Int64, pid: Int64 = 79464, flags: CGEventFlags = []) -> CGEvent {
        let sample = event(key, pid: pid, flags: flags)
        sample.type = .flagsChanged
        return sample
    }

    private func event(_ key: Int64, pid: Int64 = 79464,
                       flags: CGEventFlags = [.maskControl, .maskCommand]) -> CGEvent {
        let sample = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: true)!
        sample.setIntegerValueField(.eventSourceUnixProcessID, value: pid)
        sample.flags = flags
        return sample
    }
}

private final class ShortcutEngine: SwitchEngine {
    var directions: [SwitchDirection] = []
    var atEdge = false
    func switchSpace(_ direction: SwitchDirection) throws {
        directions.append(direction)
        if atEdge { throw SwitchEngineError.atEdge }
    }
}
