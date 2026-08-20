// SettingsWindowController.swift
// Settings window hosting a SwiftUI TabView with tabs for General, Annotation,
// Cursor, and Spotlight preferences. Each tab reads initial values from
// SettingsManager and writes changes back via .onChange observers. The window
// controller manages a single NSWindow instance reused across show calls.

import Cocoa
import SwiftUI

// MARK: - SettingsWindowController

@MainActor internal final class SettingsWindowController {

    // MARK: - Properties

    private var window: NSWindow?

    // MARK: - Show

    func showWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Spotdraw Settings"
        newWindow.contentViewController = hostingController
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = newWindow
    }
}

// MARK: - Color Presets

/// Shared color preset definitions used across settings tabs.
internal enum ColorPresets {
    /// Annotation stroke color presets (default: red).
    static let annotation: [(name: String, color: NSColor)] = [
        ("Red", .systemRed),
        ("Blue", .systemBlue),
        ("Green", .systemGreen),
        ("Yellow", .systemYellow),
        ("White", .white)
    ]

    /// Cursor highlight color presets (default: yellow).
    static let cursor: [(name: String, color: NSColor)] = [
        ("Yellow", .systemYellow),
        ("Red", .systemRed),
        ("Blue", .systemBlue),
        ("Green", .systemGreen),
        ("White", .white)
    ]
}

// MARK: - SettingsView

internal struct SettingsView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(0)
            AnnotationSettingsTab()
                .tabItem { Label("Annotation", systemImage: "pencil.tip") }
                .tag(1)
            CursorSettingsTab()
                .tabItem { Label("Cursor", systemImage: "cursorarrow") }
                .tag(2)
            SpotlightSettingsTab()
                .tabItem { Label("Spotlight", systemImage: "light.max") }
                .tag(3)
            ShortcutsSettingsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(4)
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 320)
    }
}

// MARK: - General Tab

internal struct GeneralSettingsTab: View {
    // @State properties are initialized as snapshots from SettingsManager.shared.
    // Changes are written back via .onChange but external changes are not synced back.
    @State private var fadeDuration: Double = SettingsManager.shared.fadeDuration
    @State private var launchAtLogin: Bool = false
    @State private var interactiveModeEnabled: Bool = SettingsManager.shared.interactiveModeEnabled
    @State private var passthroughModifierIndex: Int = SettingsManager.shared.passthroughModifier.rawValue

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Fade Duration:")
                        // Fade duration: 1–10s (1s for visual feedback, 10s before annotations become stale)
                        Slider(value: $fadeDuration, in: 1...10, step: 0.5) {
                            Text("Fade Duration")
                        }
                        Text("\(fadeDuration, specifier: "%.1f")s")
                            .frame(width: 40)
                    }
                    .onChangeCompat(of: fadeDuration) { newValue in
                        SettingsManager.shared.fadeDuration = newValue
                    }

                    Toggle("Launch at Login", isOn: $launchAtLogin)

                    Divider()

                    // Interactive Mode (Requirement 9.2)
                    Toggle("Interactive Mode", isOn: $interactiveModeEnabled)
                        .onChangeCompat(of: interactiveModeEnabled) { newValue in
                            SettingsManager.shared.interactiveModeEnabled = newValue
                        }
                    Text("When enabled, the overlay passes mouse events through by default. Hold the passthrough modifier to interact with annotations.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Passthrough modifier picker (Requirement 8.1)
                    HStack {
                        Text("Passthrough Modifier:")
                        Picker("", selection: $passthroughModifierIndex) {
                            ForEach(PassthroughModifier.allCases, id: \.rawValue) { modifier in
                                Text(modifier.displayName).tag(modifier.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 160)
                    }
                    .onChangeCompat(of: passthroughModifierIndex) { newValue in
                        if let modifier = PassthroughModifier(rawValue: newValue) {
                            SettingsManager.shared.passthroughModifier = modifier
                        }
                    }

                    if passthroughModifierIndex == PassthroughModifier.fn.rawValue {
                        Text("Note: macOS may intercept the Fn/Globe key for system features. Some keyboards report it inconsistently.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Annotation Tab

internal struct AnnotationSettingsTab: View {
    // @State properties are initialized as snapshots from SettingsManager.shared.
    // Changes are written back via .onChange but external changes are not synced back.
    @State private var strokeWidth: Double = Double(SettingsManager.shared.strokeWidth)
    @State private var selectedColorIndex: Int = 0
    @State private var textFontSize: Double = Double(SettingsManager.shared.textFontSize)

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Color Presets:")
                    HStack(spacing: 8) {
                        ForEach(0..<ColorPresets.annotation.count, id: \.self) { index in
                            Button(action: {
                                selectedColorIndex = index
                                SettingsManager.shared.strokeColor = ColorPresets.annotation[index].color
                            }) {
                                Circle()
                                    .fill(Color(nsColor: ColorPresets.annotation[index].color))
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(selectedColorIndex == index ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: selectedColorIndex == index ? 3 : 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(ColorPresets.annotation[index].name)
                        }
                    }

                    HStack {
                        Text("Stroke Width:")
                        // Stroke width: 1–20pt (1pt minimum for fine detail, 20pt max avoids obscuring content)
                        Slider(value: $strokeWidth, in: 1...20, step: 1) {
                            Text("Stroke Width")
                        }
                        Text("\(Int(strokeWidth))")
                            .frame(width: 30)
                    }
                    .onChangeCompat(of: strokeWidth) { newValue in
                        SettingsManager.shared.strokeWidth = CGFloat(newValue)
                    }

                    HStack {
                        Text("Text Font Size:")
                        // Text font size: 8–96pt (8pt minimum for legibility, 96pt max before it overwhelms typical displays)
                        Slider(value: $textFontSize, in: 8...96, step: 1) {
                            Text("Text Font Size")
                        }
                        Text("\(Int(textFontSize))")
                            .frame(width: 30)
                    }
                    .onChangeCompat(of: textFontSize) { newValue in
                        SettingsManager.shared.textFontSize = CGFloat(newValue)
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Cursor Tab

internal struct CursorSettingsTab: View {
    // @State properties are initialized as snapshots from SettingsManager.shared.
    // Changes are written back via .onChange but external changes are not synced back.
    @State private var highlightSize: Double = Double(SettingsManager.shared.highlightSize)
    @State private var highlightOpacity: Double = Double(SettingsManager.shared.highlightOpacity)
    @State private var selectedColorIndex: Int = 0
    @State private var glowEnabled: Bool = SettingsManager.shared.glowEnabled
    @State private var glowRadius: Double = Double(SettingsManager.shared.glowRadius)
    @State private var highlightShape: Int = SettingsManager.shared.highlightShape.rawValue
    @State private var zoomLevel: Double = Double(SettingsManager.shared.zoomLevel)
    @State private var zoomBubbleSize: Double = Double(SettingsManager.shared.zoomBubbleSize)

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Highlight Color:")
                    HStack(spacing: 8) {
                        ForEach(0..<ColorPresets.cursor.count, id: \.self) { index in
                            Button(action: {
                                selectedColorIndex = index
                                SettingsManager.shared.highlightColor = ColorPresets.cursor[index].color
                            }) {
                                Circle()
                                    .fill(Color(nsColor: ColorPresets.cursor[index].color))
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(selectedColorIndex == index ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: selectedColorIndex == index ? 3 : 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(ColorPresets.cursor[index].name)
                        }
                    }

                    HStack {
                        Text("Size:")
                        // Highlight size: 20–200pt radius (20pt for visibility, 200pt for large displays/presentations)
                        Slider(value: $highlightSize, in: 20...200, step: 5) {
                            Text("Size")
                        }
                        Text("\(Int(highlightSize))")
                            .frame(width: 30)
                    }
                    .onChangeCompat(of: highlightSize) { newValue in
                        SettingsManager.shared.highlightSize = CGFloat(newValue)
                    }

                    HStack {
                        Text("Opacity:")
                        // Opacity: 0.1–1.0 alpha (0.1 minimum ensures highlight remains visible)
                        Slider(value: $highlightOpacity, in: 0.1...1.0, step: 0.05) {
                            Text("Opacity")
                        }
                        Text("\(highlightOpacity, specifier: "%.2f")")
                            .frame(width: 40)
                    }
                    .onChangeCompat(of: highlightOpacity) { newValue in
                        SettingsManager.shared.highlightOpacity = CGFloat(newValue)
                    }

                    HStack {
                        Text("Shape:")
                        Picker("", selection: $highlightShape) {
                            ForEach(HighlightShape.allCases, id: \.rawValue) { shape in
                                Text(shape.displayName).tag(shape.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .onChangeCompat(of: highlightShape) { newValue in
                        if let shape = HighlightShape(rawValue: newValue) {
                            SettingsManager.shared.highlightShape = shape
                        }
                    }

                    Divider()

                    HStack {
                        Text("Glow Effect:")
                        Toggle("", isOn: $glowEnabled)
                            .labelsHidden()
                    }
                    .onChangeCompat(of: glowEnabled) { newValue in
                        SettingsManager.shared.glowEnabled = newValue
                    }

                    if glowEnabled {
                        HStack {
                            Text("Glow Radius:")
                            // Glow radius: 5–50pt (5pt subtle halo, 50pt dramatic bloom)
                            Slider(value: $glowRadius, in: 5...50, step: 1) {
                                Text("Glow Radius")
                            }
                            Text("\(Int(glowRadius))")
                                .frame(width: 30)
                        }
                        .onChangeCompat(of: glowRadius) { newValue in
                            SettingsManager.shared.glowRadius = CGFloat(newValue)
                        }
                    }

                    Divider()

                    // Zoom section (Requirement 5.8)
                    Text("Zoom")
                        .font(.headline)

                    HStack {
                        Text("Zoom Level:")
                        Slider(value: $zoomLevel, in: 2.0...4.0, step: 0.5) {
                            Text("Zoom Level")
                        }
                        Text("\(zoomLevel, specifier: "%.1f")x")
                            .frame(width: 40)
                    }
                    .onChangeCompat(of: zoomLevel) { newValue in
                        SettingsManager.shared.zoomLevel = CGFloat(newValue)
                    }

                    HStack {
                        Text("Bubble Size:")
                        Slider(value: $zoomBubbleSize, in: 100...300, step: 10) {
                            Text("Bubble Size")
                        }
                        Text("\(Int(zoomBubbleSize))")
                            .frame(width: 40)
                    }
                    .onChangeCompat(of: zoomBubbleSize) { newValue in
                        SettingsManager.shared.zoomBubbleSize = CGFloat(newValue)
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Spotlight Tab

internal struct SpotlightSettingsTab: View {
    // @State properties are initialized as snapshots from SettingsManager.shared.
    // Changes are written back via .onChange but external changes are not synced back.
    @State private var spotlightSize: Double = Double(SettingsManager.shared.spotlightSize)
    @State private var dimIntensity: Double = Double(SettingsManager.shared.spotlightDimIntensity)

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Spotlight Size:")
                        // Spotlight size: 50–300pt diameter (50pt usable area, 300pt for large UI elements)
                        Slider(value: $spotlightSize, in: 50...300, step: 10) {
                            Text("Spotlight Size")
                        }
                        Text("\(Int(spotlightSize))")
                            .frame(width: 40)
                    }
                    .onChangeCompat(of: spotlightSize) { newValue in
                        SettingsManager.shared.spotlightSize = CGFloat(newValue)
                    }

                    HStack {
                        Text("Dim Intensity:")
                        // Dim intensity: 0.3–0.9 alpha (below 0.3 imperceptible, above 0.9 hides content)
                        Slider(value: $dimIntensity, in: 0.3...0.9, step: 0.05) {
                            Text("Dim Intensity")
                        }
                        Text("\(dimIntensity, specifier: "%.2f")")
                            .frame(width: 40)
                    }
                    .onChangeCompat(of: dimIntensity) { newValue in
                        SettingsManager.shared.spotlightDimIntensity = CGFloat(newValue)
                    }
                }
            }
        }
        .padding()
    }
}
