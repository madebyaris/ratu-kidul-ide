import SwiftUI

/// App-wide font size settings stored in UserDefaults via @AppStorage
/// These keys can be used directly with @AppStorage in views
enum FontSettingsKeys {
    static let editorFontSize = "editorFontSize"
    static let chatFontSize = "chatFontSize"
    static let systemFontSize = "systemFontSize"
}

/// Default font sizes
enum FontSettingsDefaults {
    static let editorFontSize: Double = 13
    static let chatFontSize: Double = 14
    static let systemFontSize: Double = 13
    
    static let minFontSize: Double = 10
    static let maxFontSize: Double = 24
}

/// Observable font settings for use in ViewModels or non-View contexts
@Observable
final class FontSettings {
    static let shared = FontSettings()
    
    var editorFontSize: Double {
        get { UserDefaults.standard.double(forKey: FontSettingsKeys.editorFontSize).nonZeroOr(FontSettingsDefaults.editorFontSize) }
        set { UserDefaults.standard.set(newValue, forKey: FontSettingsKeys.editorFontSize) }
    }
    
    var chatFontSize: Double {
        get { UserDefaults.standard.double(forKey: FontSettingsKeys.chatFontSize).nonZeroOr(FontSettingsDefaults.chatFontSize) }
        set { UserDefaults.standard.set(newValue, forKey: FontSettingsKeys.chatFontSize) }
    }
    
    var systemFontSize: Double {
        get { UserDefaults.standard.double(forKey: FontSettingsKeys.systemFontSize).nonZeroOr(FontSettingsDefaults.systemFontSize) }
        set { UserDefaults.standard.set(newValue, forKey: FontSettingsKeys.systemFontSize) }
    }
    
    private init() {}
}

// MARK: - Helper Extension

private extension Double {
    func nonZeroOr(_ defaultValue: Double) -> Double {
        self == 0 ? defaultValue : self
    }
}

// MARK: - Font Helpers

extension Font {
    /// Creates a system font with the editor font size
    static var editorFont: Font {
        let size = UserDefaults.standard.double(forKey: FontSettingsKeys.editorFontSize)
            .nonZeroOr(FontSettingsDefaults.editorFontSize)
        return .system(size: size, design: .monospaced)
    }
    
    /// Creates a system font with the chat font size
    static var chatFont: Font {
        let size = UserDefaults.standard.double(forKey: FontSettingsKeys.chatFontSize)
            .nonZeroOr(FontSettingsDefaults.chatFontSize)
        return .system(size: size)
    }
    
    /// Creates a system font with the system-wide font size
    static var appFont: Font {
        let size = UserDefaults.standard.double(forKey: FontSettingsKeys.systemFontSize)
            .nonZeroOr(FontSettingsDefaults.systemFontSize)
        return .system(size: size)
    }
}

