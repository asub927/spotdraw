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
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 320)
    }
}

// MARK: - General Tab

internal struct GeneralSettingsTab: View {
    @State private var fadeDuration: Double = SettingsManager.shared.fadeDuration
    @State private var launchAtLogin: Bool = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Fade Duration:")
                        Slider(value: $fadeDuration, in: 1...10, step: 0.5) {
                            Text("Fade Duration")
                        }
                        Text("\(fadeDuration, specifier: "%.1f")s")
                            .frame(width: 40)
                    }
                    .onChange(of: fadeDuration) { newValue in
                        SettingsManager.shared.fadeDuration = newValue
                    }

                    Toggle("Launch at Login", isOn: $launchAtLogin)
                }
            }
        }
        .padding()
    }
}

// MARK: - Annotation Tab

internal struct AnnotationSettingsTab: View {
    @State private var strokeWidth: Double = Double(SettingsManager.shared.strokeWidth)
    @State private var selectedColorIndex: Int = 0

    private let colorPresets: [(String, NSColor)] = [
        ("Red", .systemRed),
        ("Blue", .systemBlue),
        ("Green", .systemGreen),
        ("Yellow", .systemYellow),
        ("White", .white)
    ]

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Color Presets:")
                    HStack(spacing: 8) {
                        ForEach(0..<5, id: \.self) { index in
                            Button(action: {
                                selectedColorIndex = index
                                SettingsManager.shared.strokeColor = colorPresets[index].1
                            }) {
                                Circle()
                                    .fill(Color(nsColor: colorPresets[index].1))
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(selectedColorIndex == index ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: selectedColorIndex == index ? 3 : 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(colorPresets[index].0)
                        }
                    }

                    HStack {
                        Text("Stroke Width:")
                        Slider(value: $strokeWidth, in: 1...20, step: 1) {
                            Text("Stroke Width")
                        }
                        Text("\(Int(strokeWidth))")
                            .frame(width: 30)
                    }
                    .onChange(of: strokeWidth) { newValue in
                        SettingsManager.shared.strokeWidth = CGFloat(newValue)
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Cursor Tab

internal struct CursorSettingsTab: View {
    @State private var highlightSize: Double = Double(SettingsManager.shared.highlightSize)
    @State private var highlightOpacity: Double = Double(SettingsManager.shared.highlightOpacity)
    @State private var selectedColorIndex: Int = 0

    private let colorPresets: [(String, NSColor)] = [
        ("Yellow", .systemYellow),
        ("Red", .systemRed),
        ("Blue", .systemBlue),
        ("Green", .systemGreen),
        ("White", .white)
    ]

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Highlight Color:")
                    HStack(spacing: 8) {
                        ForEach(0..<5, id: \.self) { index in
                            Button(action: {
                                selectedColorIndex = index
                                SettingsManager.shared.highlightColor = colorPresets[index].1
                            }) {
                                Circle()
                                    .fill(Color(nsColor: colorPresets[index].1))
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(selectedColorIndex == index ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: selectedColorIndex == index ? 3 : 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(colorPresets[index].0)
                        }
                    }

                    HStack {
                        Text("Size:")
                        Slider(value: $highlightSize, in: 20...100, step: 5) {
                            Text("Size")
                        }
                        Text("\(Int(highlightSize))")
                            .frame(width: 30)
                    }
                    .onChange(of: highlightSize) { newValue in
                        SettingsManager.shared.highlightSize = CGFloat(newValue)
                    }

                    HStack {
                        Text("Opacity:")
                        Slider(value: $highlightOpacity, in: 0.1...1.0, step: 0.05) {
                            Text("Opacity")
                        }
                        Text("\(highlightOpacity, specifier: "%.2f")")
                            .frame(width: 40)
                    }
                    .onChange(of: highlightOpacity) { newValue in
                        SettingsManager.shared.highlightOpacity = CGFloat(newValue)
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Spotlight Tab

internal struct SpotlightSettingsTab: View {
    @State private var spotlightSize: Double = Double(SettingsManager.shared.spotlightSize)
    @State private var dimIntensity: Double = Double(SettingsManager.shared.spotlightDimIntensity)

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Spotlight Size:")
                        Slider(value: $spotlightSize, in: 50...300, step: 10) {
                            Text("Spotlight Size")
                        }
                        Text("\(Int(spotlightSize))")
                            .frame(width: 40)
                    }
                    .onChange(of: spotlightSize) { newValue in
                        SettingsManager.shared.spotlightSize = CGFloat(newValue)
                    }

                    HStack {
                        Text("Dim Intensity:")
                        Slider(value: $dimIntensity, in: 0.3...0.9, step: 0.05) {
                            Text("Dim Intensity")
                        }
                        Text("\(dimIntensity, specifier: "%.2f")")
                            .frame(width: 40)
                    }
                    .onChange(of: dimIntensity) { newValue in
                        SettingsManager.shared.spotlightDimIntensity = CGFloat(newValue)
                    }
                }
            }
        }
        .padding()
    }
}
