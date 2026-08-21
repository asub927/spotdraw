// AccessibilityManager.swift
// macOS Accessibility permission checking and requesting.
// Provides static helpers to verify whether the app has been granted
// Accessibility access and to prompt the user via the system dialog.

import Cocoa

// MARK: - AccessibilityManager

public final class AccessibilityManager {

    // MARK: - Permission Check

    /// Returns `true` if the app has been granted Accessibility permission.
    public static func checkPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    // MARK: - Permission Request

    /// Prompts the user to grant Accessibility permission if not already authorized.
    /// Shows the system Accessibility preferences dialog.
    public static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
