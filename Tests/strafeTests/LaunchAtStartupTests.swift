import ServiceManagement
import XCTest
@testable import strafe

final class LaunchAtStartupTests: XCTestCase {
    @MainActor
    func testOptInAndOut() throws {
        let service = StubLoginItemService()
        let launch = LaunchAtStartup(service: service)
        XCTAssertEqual(launch.status, .notRegistered)
        XCTAssertEqual(service.registerCalls, 0)

        try launch.toggle()
        XCTAssertEqual(launch.status, .enabled)
        XCTAssertEqual(service.registerCalls, 1)

        try launch.toggle()
        XCTAssertEqual(launch.status, .notRegistered)
        XCTAssertEqual(service.unregisterCalls, 1)
    }

    @MainActor
    func testApprovalCanBeCancelledWithoutRegisteringAgain() throws {
        let service = StubLoginItemService()
        service.registrationStatus = .requiresApproval
        let launch = LaunchAtStartup(service: service)

        try launch.toggle()
        XCTAssertEqual(launch.status, .requiresApproval)
        try launch.toggle()
        XCTAssertEqual(launch.status, .notRegistered)
        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertEqual(service.unregisterCalls, 1)
    }

    @MainActor
    func testReflectsSystemSettingsChanges() throws {
        let service = StubLoginItemService()
        let launch = LaunchAtStartup(service: service)
        service.status = .enabled
        XCTAssertEqual(launch.status, .enabled)
        service.status = .requiresApproval
        XCTAssertEqual(launch.status, .requiresApproval)
        service.status = .notRegistered
        XCTAssertEqual(launch.status, .notRegistered)

        try launch.toggle()
        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertEqual(service.unregisterCalls, 0)
    }

    @MainActor
    func testFailedChangesPreserveSystemStatus() {
        let service = StubLoginItemService()
        service.error = NSError(domain: "LaunchAtStartupTests", code: 1)
        let launch = LaunchAtStartup(service: service)
        XCTAssertThrowsError(try launch.toggle())
        XCTAssertEqual(launch.status, .notRegistered)

        service.status = .enabled
        XCTAssertThrowsError(try launch.toggle())
        XCTAssertEqual(launch.status, .enabled)
    }
}

@MainActor
private final class StubLoginItemService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var registrationStatus: SMAppService.Status = .enabled
    var registerCalls = 0
    var unregisterCalls = 0
    var error: Error?

    func register() throws {
        registerCalls += 1
        if let error { throw error }
        status = registrationStatus
    }

    func unregister() throws {
        unregisterCalls += 1
        if let error { throw error }
        status = .notRegistered
    }
}
