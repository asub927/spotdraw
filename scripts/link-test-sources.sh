#!/bin/bash
# link-test-sources.sh — Idempotent test-source symlink refresh.
#
# SpotdrawTests/ shares production sources with Spotdraw/ by symlink, not by
# copy. Real copies drift silently (see design.md Decision 5 — this is what
# happened to AccessibilityManager.swift). This script keeps every eligible
# production file symlinked under SpotdrawTests/ so the test target always
# compiles the current source.
#
# Run this after adding any new production file under Spotdraw/ (excluding
# Spotdraw/App/, which is the executable entry point and is never part of
# the test target).
#
# Safe to re-run: replaces whatever currently occupies the destination path
# (real file, stale symlink, or nothing) with a fresh symlink to the current
# production source. Never leaves a .bak sibling and never fails because a
# real file already exists at the destination.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

TESTS_DIR="SpotdrawTests"

if [ ! -d "$TESTS_DIR" ]; then
  echo "error: $TESTS_DIR not found relative to repo root ($REPO_ROOT)" >&2
  exit 1
fi

while IFS= read -r -d '' src; do
  base="$(basename "$src")"
  dest="$TESTS_DIR/$base"

  # Remove whatever currently occupies dest — real file, real copy, or an
  # existing symlink (possibly stale/relative to an old location) — before
  # relinking. -f on rm handles the "doesn't exist yet" case without erroring.
  rm -f "$dest"

  # Relative path from SpotdrawTests/ back to the production source.
  ln -sf "../$src" "$dest"

  echo "linked: $dest -> ../$src"
done < <(find Spotdraw -name '*.swift' -not -path '*/App/*' -print0 | sort -z)
