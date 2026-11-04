#!/bin/zsh
# Builds a synthetic raw recording, runs the real comping code (finpro/Data/Composition)
# on the Mac and checks duration, cut accuracy, vocal sync, crossfades and partial export.
# Run before opening a PR that touches finpro/Data/Composition.
set -euo pipefail

ROOT="${0:A:h:h}"
WORK="$(mktemp -d)"

xcrun swiftc -D DEBUG \
  $(find "$ROOT/finpro/Domain" -name '*.swift') \
  $(find "$ROOT/finpro/Data/Composition" -name '*.swift') \
  "$ROOT/finpro/Shared/Storage/SessionFiles.swift" \
  "$ROOT/scripts/comping-check/main.swift" \
  -o "$WORK/comping-check"

"$WORK/comping-check" "$WORK"
