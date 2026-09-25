import Foundation
import ServiceManagement

/// Thin wrapper over SMAppService for "launch at login". The app registers itself
/// as a login item; macOS persists it across reboots.
@MainActor
final class LoginItem: ObservableObject {
    static let shared = LoginItem()

    @Published var isEnabled: Bool = (SMAppService.mainApp.status == .enabled)

    func refresh() {
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
        } catch {
            #if DEBUG
            FileHandle.standardError.write(Data("[ClaudeMonitor] login-item toggle failed: \(error)\n".utf8))
            #endif
        }
        refresh()
    }
}
