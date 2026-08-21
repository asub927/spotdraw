#!/bin/bash
# setup-testing-framework.sh
#
# On CLT-only macOS machines (no Xcode), the Testing.framework and
# lib_TestingInterop.dylib are not in the standard rpath locations that
# SwiftPM's test runner expects. This script creates symlinks in the
# .build directory so `swift test` can load the test bundle at runtime.
#
# Run this after `swift build` or before `swift test` for property tests.
# The symlinks are idempotent and harmless on Xcode-based machines.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DEBUG_DIR="$PROJECT_DIR/.build/arm64-apple-macosx/debug"

TESTING_FW="/Library/Developer/CommandLineTools/Library/Developer/Frameworks/Testing.framework"
TESTING_INTEROP="/Library/Developer/CommandLineTools/Library/Developer/usr/lib/lib_TestingInterop.dylib"

# Ensure build directory exists
mkdir -p "$BUILD_DEBUG_DIR"

# Symlink Testing.framework
if [ -d "$TESTING_FW" ] && [ ! -e "$BUILD_DEBUG_DIR/Testing.framework" ]; then
    ln -sf "$TESTING_FW" "$BUILD_DEBUG_DIR/Testing.framework"
    echo "✓ Symlinked Testing.framework"
elif [ -e "$BUILD_DEBUG_DIR/Testing.framework" ]; then
    echo "· Testing.framework already linked"
else
    echo "✗ Testing.framework not found at $TESTING_FW"
    echo "  Install Xcode or Command Line Tools with Swift Testing support"
    exit 1
fi

# Symlink lib_TestingInterop.dylib
if [ -f "$TESTING_INTEROP" ] && [ ! -e "$BUILD_DEBUG_DIR/lib_TestingInterop.dylib" ]; then
    ln -sf "$TESTING_INTEROP" "$BUILD_DEBUG_DIR/lib_TestingInterop.dylib"
    echo "✓ Symlinked lib_TestingInterop.dylib"
elif [ -e "$BUILD_DEBUG_DIR/lib_TestingInterop.dylib" ]; then
    echo "· lib_TestingInterop.dylib already linked"
else
    echo "✗ lib_TestingInterop.dylib not found at $TESTING_INTEROP"
    exit 1
fi

echo "Done. Run: swift test -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks"
