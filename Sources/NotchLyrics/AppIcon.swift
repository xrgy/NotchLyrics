import AppKit
import Foundation

public enum AppIcon {
    public static func image() -> NSImage? {
        if let icon = NSImage(named: NSImage.Name("NotchLyrics")) {
            return icon
        }

        guard let url = Bundle.main.url(forResource: "NotchLyrics", withExtension: "icns") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
