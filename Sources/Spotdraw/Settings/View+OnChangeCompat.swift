// View+OnChangeCompat.swift
// Cross-version `.onChange` wrapper that uses the modern two-parameter form on
// macOS 14+ and falls back to the legacy single-parameter form on macOS 13.

import SwiftUI

extension View {
    /// A compatibility wrapper for `.onChange` that eliminates deprecation warnings
    /// on macOS 14+ while maintaining macOS 13 backward compatibility.
    @ViewBuilder
    func onChangeCompat<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self.onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            self.onChange(of: value) { newValue in
                action(newValue)
            }
        }
    }
}
