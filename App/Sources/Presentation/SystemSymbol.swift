import AppKit

enum SystemSymbol {
    static func isRenderable(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}
