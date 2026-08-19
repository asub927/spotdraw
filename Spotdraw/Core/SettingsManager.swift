// SettingsManager.swift
// Persistent settings storage via UserDefaults with typed accessors.
// Exposes annotation, cursor highlight, and spotlight preferences as
// strongly-typed properties. Uses NSKeyedArchiver for NSColor storage.
// Accessed as a singleton throughout the app.

import Cocoa

// MARK: - HighlightShape

internal enum HighlightShape: Int, CaseIterable {
    case circle = 0
    case ring = 1
    case square = 2
    case crosshair = 3

    var displayName: String {
        switch self {
        case .circle: "Circle"
        case .ring: "Ring"
        case .square: "Square"
        case .crosshair: "Crosshair"
        }
    }
}

// MARK: - SettingsManager

@MainActor internal final class SettingsManager {

    // MARK: - Singleton

    nonisolated(unsafe) static let shared = SettingsManager()

    // MARK: - Keys

    private enum Keys {
        static let strokeColor = "strokeColor"
        static let strokeWidth = "strokeWidth"
        static let highlightColor = "highlightColor"
        static let highlightSize = "highlightSize"
        static let highlightOpacity = "highlightOpacity"
        static let spotlightSize = "spotlightSize"
        static let spotlightDimIntensity = "spotlightDimIntensity"
        static let fadeMode = "fadeMode"
        static let fadeDuration = "fadeDuration"
        static let glowEnabled = "glowEnabled"
        static let glowRadius = "glowRadius"
        static let highlightShape = "highlightShape"
        static let textFontSize = "textFontSize"
    }

    // MARK: - Annotation Settings

    var strokeColor: NSColor {
        get { colorForKey(Keys.strokeColor) ?? .systemRed }
        set { setColor(newValue, forKey: Keys.strokeColor) }
    }

    var strokeWidth: CGFloat {
        get { CGFloat(UserDefaults.standard.float(forKey: Keys.strokeWidth)).clamped(to: 1...20) }
        set { UserDefaults.standard.set(Float(newValue), forKey: Keys.strokeWidth) }
    }

    var fadeMode: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.fadeMode) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.fadeMode) }
    }

    var fadeDuration: TimeInterval {
        get {
            let val = UserDefaults.standard.double(forKey: Keys.fadeDuration)
            return val > 0 ? val : 3.0
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.fadeDuration) }
    }

    var textFontSize: CGFloat {
        get {
            let val = CGFloat(UserDefaults.standard.float(forKey: Keys.textFontSize))
            return val > 0 ? val.clamped(to: 8...96) : 24.0
        }
        set { UserDefaults.standard.set(Float(newValue), forKey: Keys.textFontSize) }
    }

    // MARK: - Cursor Highlight Settings

    var highlightColor: NSColor {
        get { colorForKey(Keys.highlightColor) ?? .systemYellow }
        set { setColor(newValue, forKey: Keys.highlightColor) }
    }

    var highlightSize: CGFloat {
        get {
            let val = CGFloat(UserDefaults.standard.float(forKey: Keys.highlightSize))
            return val > 0 ? val.clamped(to: 20...200) : 40.0
        }
        set { UserDefaults.standard.set(Float(newValue), forKey: Keys.highlightSize) }
    }

    var highlightOpacity: CGFloat {
        get {
            let val = CGFloat(UserDefaults.standard.float(forKey: Keys.highlightOpacity))
            return val > 0 ? val : 0.4
        }
        set { UserDefaults.standard.set(Float(newValue), forKey: Keys.highlightOpacity) }
    }

    // MARK: - Glow Settings

    var glowEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.glowEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.glowEnabled) }
    }

    var glowRadius: CGFloat {
        get {
            let val = CGFloat(UserDefaults.standard.float(forKey: Keys.glowRadius))
            return val > 0 ? val.clamped(to: 5...50) : 15.0
        }
        set { UserDefaults.standard.set(Float(newValue), forKey: Keys.glowRadius) }
    }

    // MARK: - Highlight Shape Setting

    var highlightShape: HighlightShape {
        get {
            let raw = UserDefaults.standard.integer(forKey: Keys.highlightShape)
            return HighlightShape(rawValue: raw) ?? .circle
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Keys.highlightShape) }
    }

    // MARK: - Spotlight Settings

    var spotlightSize: CGFloat {
        get {
            let val = CGFloat(UserDefaults.standard.float(forKey: Keys.spotlightSize))
            return val > 0 ? val : 150.0
        }
        set { UserDefaults.standard.set(Float(newValue), forKey: Keys.spotlightSize) }
    }

    var spotlightDimIntensity: CGFloat {
        get {
            let val = CGFloat(UserDefaults.standard.float(forKey: Keys.spotlightDimIntensity))
            return val > 0 ? val : 0.7
        }
        set { UserDefaults.standard.set(Float(newValue), forKey: Keys.spotlightDimIntensity) }
    }

    // MARK: - Color Helpers

    private func colorForKey(_ key: String) -> NSColor? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
    }

    private func setColor(_ color: NSColor, forKey key: String) {
        let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true)
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: - Init

    private nonisolated init() {
        registerDefaults()
    }

    private nonisolated func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.strokeWidth: 3.0,
            Keys.highlightSize: 40.0,
            Keys.highlightOpacity: 0.4,
            Keys.spotlightSize: 150.0,
            Keys.spotlightDimIntensity: 0.7,
            Keys.fadeMode: false,
            Keys.fadeDuration: 3.0,
            Keys.glowEnabled: true,
            Keys.glowRadius: 15.0,
            Keys.highlightShape: 0,
            Keys.textFontSize: 24.0
        ])
    }
}

// MARK: - CGFloat Clamping

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        if self < range.lowerBound { return range.lowerBound }
        if self > range.upperBound { return range.upperBound }
        return self
    }
}
