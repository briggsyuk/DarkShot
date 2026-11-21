import ServiceManagement

@MainActor
final class LaunchAtLogin {
    var status: SMAppService.Status { SMAppService.mainApp.status }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if status == .notRegistered || status == .notFound { try SMAppService.mainApp.register() }
        } else if status == .enabled || status == .requiresApproval {
            try SMAppService.mainApp.unregister()
        }
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
