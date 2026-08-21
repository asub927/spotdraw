// SettingsManager.swift
// Persistent settings storage via UserDefaults with typed accessors.
// Exposes annotation, cursor highlight, and spotlight preferences as
// strongly-typed properties. Uses NSKeyedArchiver for NSColor storage.
// Accessed as a singleton throughout the app.

import Cocoa

// MARK: - HighlightShape

public enum HighlightShape: Int, CaseIterable {
    case circle = 0
    case ring = 1
    case square = 2
    case crosshair = 3

    public var displayName: String {
        switch self {
        case .circle: "Circle"
        case .ring: "Ring"
        case .square: "Square"
        case .crosshair: "Crosshair"
        }
    }
}

// MARK: - SettingsManager

@MainActor public final class SettingsManager {

    // MARK: - Singleton

    nonisolated(unsafe) public static let shared = SettingsManager()

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
        static let zoomLevel = "zoomLevel"
        static let zoomBubbleSize = "zoomBubbleSize"
        static let interactiveModeEnabled = "interactiveModeEnabled"
        static let passthroughModifier = "passthroughModifier"
        // State restoration (Requirement 5)
        static let lastActiveTool = "lastActiveTool"
        static let lastActiveColor = "lastActiveColor"
        static let toolbarPanelX = "toolbarPanelX"
        static let toolbarPanelY = "toolbarPanelY"
        static let wasAnnotationActive = "wasAnnotationActive"
        static let wasHighlightActive = "wasHighlightActive"
        static let wasSpotlightActive = "wasSpotlightActive"
        static let wasZoomActive = "wasZoomActive"
    }

    // MARK: - Annotation Settings

    public var strokeColor: NSColor {
        get { colorForKey(Keys.strokeColor) ?? .systemRed }
        set { setColor(newValue, forKey: Keys.strokeColor) }
    }

    public var strokeWidth: CGFloat {
        get { CGFloat(UserDefaults.standard.float(forKey: Keys.strokeWidth)).clamped(to: 1...20) }
        set { UserDefaults.standard.set(Float(newValue), forKey: Keys.strokeWidth) }
    }

    public var fadeMode: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.fadeMode) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.fadeMode) }
    }

    public var fadeDuration: TimeInterval {
        get {
            let val = UserDefaults.standard.double(forKey: Keys.fadeDuration)
            return val > 0 ? val : 3.0
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.fadeDuration) }
    }

    public var textFontSize: CGFloat {
        get {
            let val = CGFloat(UserDefaults.standard.float(forKey: Keys.textFontSize))
            return val > 0 ? val.clamped(to: 8...96) : 24.0
        }
        set { UserDefaults.standard.set(Float(newValue), forKey: Keys.textFontSize) }
    }

    // MARK: - Zoom Settings

    public var zoomLevel: CGFloat {
        get {
            let val = CGFloat(UserDefaults.standard.float(forKey: Keys.zoomLevel))
            return val > 0 ? val.clamped(to: 2.0...4.0) : 2.0
        }
        set { UserDefaults.standard.set(Float(newValue.clamped(to: 2.0...4.0)), forKey: Keys.zoomLevel) }
    }

    public var zoomBubbleSize: CGFloat {
        get {
            let val = CGFloat(UserDefaults.standard.float(forKey: Keys.zoomBubbleSize))
            return val > 0 ? val.clamped(to: 100...300) : 200.0
        }
        set { UserDefaults.standard.set(Float(newValue.clamped(to: 100...300)), forKey: Keys.zoomBubbleSize) }
    }

    // MARK: - Interactive Mode Settings

    /// Whether Interactive Mode is enabled. When true, the overlay defaults to
    /// passthrough and requires the modifier to be held for capturing. Requirement 9.1.
    public var interactiveModeEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.interactiveModeEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.interactiveModeEnabled) }
    }

    /// The configured passthrough modifier. Defaults to `.rightOption`. Requirement 8.1.
    public var passthroughModifier: PassthroughModifier {
        get {
            let raw = UserDefaults.standard.integer(forKey: Keys.passthroughModifier)
            return PassthroughModifier(rawValue: raw) ?? .rightOption
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Keys.passthroughModifier) }
    }

    // MARK: - State Restoration (Requirement 5)

    /// The last active tool name, persisted as a string matching ToolType cases.
    public var lastActiveTool: String {
        get { UserDefaults.standard.string(forKey: Keys.lastActiveTool) ?? "pen" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lastActiveTool) }
    }

    /// The last active annotation color.
    public var lastActiveColor: NSColor {
        get { colorForKey(Keys.lastActiveColor) ?? .systemRed }
        set { setColor(newValue, forKey: Keys.lastActiveColor) }
    }

    /// Toolbar panel X position (screen coordinates).
    public var toolbarPanelX: CGFloat {
        get { CGFloat(UserDefaults.standard.float(forKey: Keys.toolbarPanelX)) }
        set { UserDefaults.standard.set(Float(newValue), forKey: Keys.toolbarPanelX) }
    }

    /// Toolbar panel Y position (screen coordinates).
    public var toolbarPanelY: CGFloat {
        get { CGFloat(UserDefaults.standard.float(forKey: Keys.toolbarPanelY)) }
        set { UserDefaults.standard.set(Float(newValue), forKey: Keys.toolbarPanelY) }
    }

    /// Whether toolbar panel position has been saved at least once.
    public var hasToolbarPanelPosition: Bool {
        UserDefaults.standard.object(forKey: Keys.toolbarPanelX) != nil
    }

    /// Whether annotation overlay was active when app last terminated.
    public var wasAnnotationActive: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.wasAnnotationActive) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.wasAnnotationActive) }
    }

    /// Whether cursor highlight was active when app last terminated.
    public var wasHighlightActive: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.wasHighlightActive) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.wasHighlightActive) }
    }

    /// Whether spotlight was active when app last terminated.
    public var wasSpotlightActive: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.wasSpotlightActive) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.wasSpotlightActive) }
    }

    /// Whether zoom was active when app last terminated.
    public var wasZoomActive: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.wasZoomActive) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.wasZoomActive) }
    }

    // MARK: - Cursor Highlight Settings

    public var highlightColor: NSColor {
        get { colorForKey(Keys.highlightColor) ?? .systemYellow }
        set { setColor(newValue, forKey: Keys.highlightColor) }
    }

    public var highlightSize: CGFloat {
        get {
            let val = CGFloat(UserDefaults.standard.float(forKey: Keys.highlightSize))
            return val > 0 ? val.clamped(to: 20...200) : 40.0
        }
        set { UserDefaults.standard.set(Float(newValue), forKey: Keys.highlightSize) }
    }

    public var highlightOpacity: CGFloat {
        get {
            let val = CGFloat(UserDefaults.standard.float(forKey: Keys.highlightOpacity))
            return val > 0 ? val : 0.4
        }
        set { UserDefaults.standard.set(Float(newValue), forKey: Keys.highlightOpacity) }
    }

    // MARK: - Glow Settings

    public var glowEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.glowEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.glowEnabled) }
    }

    public var glowRadius: CGFloat {
        get {
            let val = CGFloat(UserDefaults.standard.float(forKey: Keys.glowRadius))
            return val > 0 ? val.clamped(to: 5...50) : 15.0
        }
        set { UserDefaults.standard.set(Float(newValue), forKey: Keys.glowRadius) }
    }

    // MARK: - Highlight Shape Setting

    public var highlightShape: HighlightShape {
        get {
            let raw = UserDefaults.standard.integer(forKey: Keys.highlightShape)
            return HighlightShape(rawValue: raw) ?? .circle
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Keys.highlightShape) }
    }

    // MARK: - Spotlight Settings

    public var spotlightSize: CGFloat {
        get {
            let val = CGFloat(UserDefaults.standard.float(forKey: Keys.spotlightSize))
            return val > 0 ? val : 150.0
        }
        set { UserDefaults.standard.set(Float(newValue), forKey: Keys.spotlightSize) }
    }

    public var spotlightDimIntensity: CGFloat {
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
            Keys.textFontSize: 24.0,
            Keys.zoomLevel: 2.0,
            Keys.zoomBubbleSize: 200.0,
            Keys.interactiveModeEnabled: false,
            Keys.passthroughModifier: PassthroughModifier.rightOption.rawValue,
            Keys.lastActiveTool: "pen",
            Keys.wasAnnotationActive: false,
            Keys.wasHighlightActive: false,
            Keys.wasSpotlightActive: false,
            Keys.wasZoomActive: false
        ])
    }
}

// MARK: - CGFloat Clamping

extension CGFloat {
    public func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        if self < range.lowerBound { return range.lowerBound }
        if self > range.upperBound { return range.upperBound }
        return self
    }
}
