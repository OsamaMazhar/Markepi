#!/usr/bin/env bash
# build-gate.sh — xcodebuild verification for all 3 targets
# Runs xcodebuild across WatermarkApp, ShareExtension, PhotoEditExtension
# via the single WatermarkApp scheme. Propagates xcodebuild exit code.
set -euo pipefail

# Resolve project root (script may be called from any CWD under repo)
REPO_ROOT=$(git rev-parse --show-toplevel)
PROJECT="$REPO_ROOT/Watermark.xcodeproj"

echo "=== Build Gate: WatermarkApp (all targets) ==="
echo ""

# xcodebuild outputs to stdout/stderr transparently — no tee, no buffering,
# no redirect (per RESEARCH.md: suppressing output defeats the gate's purpose).
xcodebuild \
  -project "$PROJECT" \
  -scheme WatermarkApp \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build

BUILD_EXIT=$?

echo ""
if [ $BUILD_EXIT -eq 0 ]; then
  echo "BUILD GATE: PASSED"
  exit 0
else
  echo "BUILD GATE: FAILED — see errors above"
  exit $BUILD_EXIT
fi
