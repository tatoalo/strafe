import ServiceManagement

@MainActor
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

@MainActor
final class LaunchAtStartup {
    private let service: any LoginItemService

    init(service: any LoginItemService = SMAppService.mainApp) {
        self.service = service
    }

    var status: SMAppService.Status { service.status }

    func toggle() throws {
        switch service.status {
        case .enabled, .requiresApproval:
            try service.unregister()
        default:
            try service.register()
        }
    }
}
