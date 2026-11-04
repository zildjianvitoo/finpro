#!/bin/zsh
# Compiles finpro/Domain (plus the pure LoopStateController) with every scripts/domain-checks/*Checks.swift on the Mac and runs them.
# Run before opening a PR that touches finpro/Domain/UseCases.
set -euo pipefail

ROOT="${0:A:h:h}"
WORK="$(mktemp -d)"

xcrun swiftc -D DEBUG \
  $(find "$ROOT/finpro/Domain" -name '*.swift') \
  "$ROOT/finpro/Presentation/Recording/LoopStateController.swift" \
  $(find "$ROOT/scripts/domain-checks" -name '*.swift') \
  -o "$WORK/domain-check"

"$WORK/domain-check"
