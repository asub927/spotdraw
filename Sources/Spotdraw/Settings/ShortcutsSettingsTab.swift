// ShortcutsSettingsTab.swift
// Shortcuts settings tab showing all bindable actions grouped by category.
// Provides record, clear, and reset controls per row, plus a reset-all control.
// Uses an NSViewRepresentable key-capture view for Recording_State since SwiftUI
// has no raw-key-capture affordance. Observes ShortcutStore.didChangeNotification
// to stay in sync with external changes.

import Cocoa
import SwiftUI
import Combine
import SpotdrawCore

// MARK: - ShortcutsSettingsTab

internal struct ShortcutsSettingsTab: View {
    @StateObject private var viewModel = ShortcutsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.recordingAction != nil {
                KeyCaptureView(viewModel: viewModel)
                    .frame(width: 0, height: 0)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(ShortcutCategory.allCases, id: \.rawValue) { category in
                        ShortcutCategorySection(
                            category: category,
                            viewModel: viewModel
                        )
                    }
                }
                .padding(.horizontal, 4)
            }

            Divider()

            HStack {
                Button("Reset All to Defaults") {
                    viewModel.resetAll()
                }
                Spacer()
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 360)
        .onDisappear {
            // Ensure recording suppression is cleared if the tab disappears
            viewModel.cancelRecording()
        }
    }
}

// MARK: - ShortcutsViewModel

internal final class ShortcutsViewModel: ObservableObject {
    @Published var recordingAction: ShortcutAction?
    @Published var conflictMessage: String?
    @Published var conflictAction: ShortcutAction?
    @Published var pendingBinding: KeyBinding?
    @Published var errorMessage: String?
    @Published private var refreshToken: Int = 0

    /// Notification observer token.
    private var observer: Any?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: ShortcutStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshToken += 1
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        // Ensure recording suppression is cleared on teardown
        HotkeyManager.shared?.isRecordingSuppressed = false
    }

    // MARK: - Recording State

    func startRecording(for action: ShortcutAction) {
        recordingAction = action
        conflictMessage = nil
        conflictAction = nil
        pendingBinding = nil
        errorMessage = nil
        // Suppress global shortcuts while recording (Requirement 7.16)
        HotkeyManager.shared?.isRecordingSuppressed = true
    }

    func cancelRecording() {
        recordingAction = nil
        conflictMessage = nil
        conflictAction = nil
        pendingBinding = nil
        errorMessage = nil
        HotkeyManager.shared?.isRecordingSuppressed = false
    }

    func handleCapturedKey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        guard let action = recordingAction else { return }

        let relevantMods: NSEvent.ModifierFlags = [.control, .shift, .option, .command]
        let binding = KeyBinding(keyCode: keyCode, modifiers: modifiers.intersection(relevantMods))

        // Reject zero-modifier candidate for global actions (Requirement 7.11)
        if action.scope == .global && binding.modifierRawValue == 0 {
            errorMessage = "Global shortcuts require at least one modifier key."
            return
        }

        // Check for conflicts within the same scope (Requirement 7.8)
        if let conflict = ShortcutStore.shared.conflictingAction(for: binding, excluding: action) {
            conflictMessage = "\"\(binding.displayString)\" is already assigned to \"\(conflict.displayName)\"."
            conflictAction = conflict
            pendingBinding = binding
            return
        }

        // No conflict — assign directly (Requirement 7.7)
        ShortcutStore.shared.assign(binding, to: action)
        finishRecording()
    }

    func confirmConflictReplacement() {
        guard let action = recordingAction,
              let binding = pendingBinding,
              let conflict = conflictAction else { return }

        // Clear the conflicting action and assign the new binding (Requirement 7.9)
        ShortcutStore.shared.clear(conflict)
        ShortcutStore.shared.assign(binding, to: action)
        finishRecording()
    }

    func clearAction(_ action: ShortcutAction) {
        ShortcutStore.shared.clear(action)
    }

    func resetAction(_ action: ShortcutAction) {
        ShortcutStore.shared.reset(action)
    }

    func resetAll() {
        ShortcutStore.shared.resetAll()
    }

    private func finishRecording() {
        recordingAction = nil
        conflictMessage = nil
        conflictAction = nil
        pendingBinding = nil
        errorMessage = nil
        HotkeyManager.shared?.isRecordingSuppressed = false
    }
}

// MARK: - ShortcutCategorySection

private struct ShortcutCategorySection: View {
    let category: ShortcutCategory
    @ObservedObject var viewModel: ShortcutsViewModel

    private var actions: [ShortcutAction] {
        ShortcutAction.allCases.filter { $0.category == category }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(category.rawValue)
                .font(.headline)
                .padding(.bottom, 4)

            ForEach(actions, id: \.rawValue) { action in
                ShortcutRow(action: action, viewModel: viewModel)
            }
        }
    }
}

// MARK: - ShortcutRow

private struct ShortcutRow: View {
    let action: ShortcutAction
    @ObservedObject var viewModel: ShortcutsViewModel

    private var isRecording: Bool {
        viewModel.recordingAction == action
    }

    private var bindingText: String {
        if isRecording {
            if let error = viewModel.errorMessage {
                return error
            }
            if let conflict = viewModel.conflictMessage {
                return conflict
            }
            return "Press a key combination..."
        }
        if let binding = ShortcutStore.shared.binding(for: action) {
            return binding.displayString
        }
        return "None"
    }

    var body: some View {
        HStack {
            Text(action.displayName)
                .frame(width: 160, alignment: .leading)

            Text(bindingText)
                .frame(minWidth: 120, alignment: .leading)
                .foregroundColor(isRecording ? .secondary : .primary)

            Spacer()

            if isRecording {
                if viewModel.conflictAction != nil {
                    Button("Replace") {
                        viewModel.confirmConflictReplacement()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                Button("Cancel") {
                    viewModel.cancelRecording()
                }
                .controlSize(.small)
            } else {
                Button("Record") {
                    viewModel.startRecording(for: action)
                }
                .controlSize(.small)

                Button("Clear") {
                    viewModel.clearAction(action)
                }
                .controlSize(.small)
                .disabled(ShortcutStore.shared.binding(for: action) == nil)

                Button("Reset") {
                    viewModel.resetAction(action)
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - KeyCaptureView (NSViewRepresentable)

/// An NSViewRepresentable that captures raw key events for shortcut recording.
/// While active, it becomes first responder and forwards key-down events to the view model.
internal struct KeyCaptureView: NSViewRepresentable {
    @ObservedObject var viewModel: ShortcutsViewModel

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKeyDown = { [weak viewModel] keyCode, modifiers in
            viewModel?.handleCapturedKey(keyCode: keyCode, modifiers: modifiers)
        }
        view.onEscape = { [weak viewModel] in
            viewModel?.cancelRecording()
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        if viewModel.recordingAction != nil {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

/// NSView subclass that captures key-down events for shortcut recording.
internal final class KeyCaptureNSView: NSView {
    var onKeyDown: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Escape cancels recording (Requirement 7.10)
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        onKeyDown?(event.keyCode, event.modifierFlags)
    }
}
