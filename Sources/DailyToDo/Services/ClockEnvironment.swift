import SwiftUI
import TodoDomain

private struct AppClockKey: EnvironmentKey { static let defaultValue = AppClock.system }
extension EnvironmentValues {
    var appClock: AppClock {
        get { self[AppClockKey.self] }
        set { self[AppClockKey.self] = newValue }
    }
}
