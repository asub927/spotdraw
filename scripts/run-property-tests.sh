#!/bin/bash
# Run SpotdrawPropertyTests with the required framework search paths.
# The PropertyBased library requires swift-testing (Testing framework), which on
# Command Line Tools needs explicit framework search paths to compile and link.
# On Xcode-based toolchains, these flags are not needed.

set -euo pipefail
cd "$(dirname "$0")/.."

TESTING_FW="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
TESTING_LIB="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

# Check if we're using Xcode (no extra flags needed) or CLT
if xcode-select -p 2>/dev/null | grep -q "Xcode.app"; then
    swift test --filter SpotdrawPropertyTests "$@"
else
    swift test --filter SpotdrawPropertyTests \
        -Xswiftc "-F${TESTING_FW}" \
        -Xlinker "-F${TESTING_FW}" \
        -Xlinker -rpath -Xlinker "${TESTING_FW}" \
        -Xlinker -rpath -Xlinker "${TESTING_LIB}" \
        "$@"
fi
