import AppKit

extension Notification.Name {
    static let macMomPreferencesChanged = Notification.Name("MacMomPreferencesChanged")
}

/// Choices from the menu-bar settings button. Stored on this Mac only.
enum MacMomPreferences {
    private static let appearanceKey = "MacMomAppearance"
    private static let notificationsKey = "MacMomNotifications"

    static var isDark: Bool {
        get {
            switch UserDefaults.standard.string(forKey: appearanceKey) {
            case "dark": return true
            case "light": return false
            default:
                return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            }
        }
        set {
            UserDefaults.standard.set(newValue ? "dark" : "light", forKey: appearanceKey)
            NotificationCenter.default.post(name: .macMomPreferencesChanged, object: nil)
        }
    }

    static var appearance: NSAppearance {
        NSAppearance(named: isDark ? .darkAqua : .aqua) ?? NSAppearance(named: .aqua)!
    }

    static var notificationsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: notificationsKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: notificationsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: notificationsKey)
            NotificationCenter.default.post(name: .macMomPreferencesChanged, object: nil)
        }
    }
}
