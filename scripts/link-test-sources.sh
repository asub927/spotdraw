#!/bin/bash
# link-test-sources.sh — Idempotent test-source symlink refresh.
#
# Tests/SpotdrawTests/ shares production sources with Sources/Spotdraw/ by
# symlink, not by copy. Real copies drift silently (see design.md Decision 5 —
# this is what happened to AccessibilityManager.swift). This script keeps every
# eligible production file symlinked (flat) under Tests/SpotdrawTests/ so the
# test target always compiles the current source.
#
# Run this after adding any new production file under Sources/Spotdraw/
# (excluding Sources/Spotdraw/App/, which is the executable entry point and is
# never part of the test target). Files in subdirectories (e.g. Overlay/,
# Overlay/ToolbarViews/) are linked flat by basename.
#
# Safe to re-run: replaces whatever currently occupies the destination path
# (real file, stale symlink, or nothing) with a fresh symlink to the current
# production source. Never leaves a .bak sibling and never fails because a
# real file already exists at the destination.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SOURCES_DIR="Sources/Spotdraw"
TESTS_DIR="Tests/SpotdrawTests"

if [ ! -d "$SOURCES_DIR" ]; then
  echo "error: $SOURCES_DIR not found relative to repo root ($REPO_ROOT)" >&2
  exit 1
fi
if [ ! -d "$TESTS_DIR" ]; then
  echo "error: $TESTS_DIR not found relative to repo root ($REPO_ROOT)" >&2
  exit 1
fi

# Guard against basename collisions: the test target links files flat by
# basename, so two production files sharing a name (in different subdirectories)
# would clobber each other. Fail loudly rather than link the wrong one.
collisions="$(find "$SOURCES_DIR" -name '*.swift' -not -path '*/App/*' -exec basename {} \; | sort | uniq -d)"
if [ -n "$collisions" ]; then
  echo "error: basename collision(s) among test-linked sources; flat linking is unsafe:" >&2
  echo "$collisions" >&2
  exit 1
fi

# Depth of TESTS_DIR below the repo root determines the "../" prefix needed to
# reach a repo-root-relative source path. Tests/SpotdrawTests → two levels.
prefix="../../"

while IFS= read -r -d '' src; do
  base="$(basename "$src")"
  dest="$TESTS_DIR/$base"

  # Remove whatever currently occupies dest — real file, real copy, or an
  # existing symlink (possibly stale/relative to an old location) — before
  # relinking. -f on rm handles the "doesn't exist yet" case without erroring.
  rm -f "$dest"

  # Relative path from Tests/SpotdrawTests/ back to the production source.
  ln -sf "${prefix}${src}" "$dest"

  echo "linked: $dest -> ${prefix}${src}"
done < <(find "$SOURCES_DIR" -name '*.swift' -not -path '*/App/*' -print0 | sort -z)
