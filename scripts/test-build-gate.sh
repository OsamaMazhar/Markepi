#!/usr/bin/env bash
# test-build-gate.sh — Self-contained fixture test for build-gate.sh
# Validates three branches: clean build, broken build caught, gate blocks progression.
# In-place mutation with git checkout restoration via trap (per D-11).
set -euo pipefail

FAILURES=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="$SCRIPT_DIR/build-gate.sh"

# Source file to mutate for broken-build test
# Non-critical, fast-compiling file from a completed phase (Phase 7)
# No Phase 10-11 plans modify this file.
TEST_FILE="$REPO_ROOT/App/Intents/WatermarkAppShortcuts.swift"

# Trap: restore source file on ANY exit (pass or fail)
# || true prevents cleanup failures from masking test results (Pitfall 3)
trap 'git -C "$REPO_ROOT" checkout -- "$TEST_FILE" 2>/dev/null || true' EXIT

echo "=== Build Gate Fixture Tests ==="
echo ""

# --- Branch 1: Clean build passes ---
echo "--- Branch 1: Clean Build ---"
if "$GATE"; then
  echo "  PASS: clean build"
else
  echo "  FAIL: clean build"
  FAILURES=$((FAILURES + 1))
fi
echo ""

# --- Branch 2: Broken build caught with error ---
echo "--- Branch 2: Broken Build Caught ---"
# Backup original
cp "$TEST_FILE" "$TEST_FILE.bak"
# Inject syntax error: incomplete let binding — guaranteed compilation error
echo 'let x =' >> "$TEST_FILE"
# Run gate and capture output + exit code (Pitfall 5 pattern)
GATE_OUTPUT=$("$GATE" 2>&1) || GATE_EXIT=$?
if [ "${GATE_EXIT:-0}" -ne 0 ]; then
  if echo "$GATE_OUTPUT" | grep -qi "error"; then
    echo "  PASS: broken build caught (exit=$GATE_EXIT, output contains error)"
  else
    echo "  FAIL: broken build exit non-zero but no error in output"
    FAILURES=$((FAILURES + 1))
  fi
else
  echo "  FAIL: broken build not caught (exit 0)"
  FAILURES=$((FAILURES + 1))
fi
# Remove backup
rm -f "$TEST_FILE.bak"
echo ""

# --- Branch 3: Gate blocks wave progression ---
echo "--- Branch 3: Gate Blocks Wave Progression ---"
# Re-inject error (trap will restore at end)
echo 'let y =' >> "$TEST_FILE"
# Run gate with stderr suppressed; assert non-zero exit
if ! "$GATE" > /dev/null 2>&1; then
  echo "  PASS: gate blocks wave progression (exit non-zero)"
else
  echo "  FAIL: gate should block but returned exit 0"
  FAILURES=$((FAILURES + 1))
fi
echo ""

# --- Final assertion ---
if [ "$FAILURES" -eq 0 ]; then
  echo "ALL TESTS PASSED"
  exit 0
else
  echo "${FAILURES} TEST(S) FAILED"
  exit 1
fi
