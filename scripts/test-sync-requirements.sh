#!/usr/bin/env bash
# Test: scripts/test-sync-requirements.sh
# Self-contained fixture test for the recurrence guard.
# Validates all three branches: happy path, not_found, already_complete.
# Inline heredoc fixtures, temp dir, trap-based cleanup (D-07).
set -euo pipefail

TESTDIR=$(mktemp -d)
# Cleanup on both pass and failure paths (Pitfall #4)
trap 'rm -rf "$TESTDIR"' EXIT

# Create .planning/ subdirectory — gsd-sdk resolves REQUIREMENTS.md relative to cwd
mkdir -p "$TESTDIR/.planning"

FAILURES=0

echo "=== Recurrence Guard Fixture Tests ==="
echo ""

# --- Fixture 1: Happy Path ---
echo "--- Fixture 1: Happy Path ---"
cat > "$TESTDIR/.planning/REQUIREMENTS.md" << 'REQEOF'
# Requirements: Watermark — Test

## Test Requirements

### Test Category

- [ ] **TEST-A01**: Test requirement one

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| TEST-A01 | Phase 99 | Pending |

**Coverage:**
- Test requirements: 1 total
- Mapped to phases: 1
REQEOF

RESULT1=$(cd "$TESTDIR" && gsd-sdk query requirements mark-complete TEST-A01 2>&1)
echo "  Result: $RESULT1"
if echo "$RESULT1" | jq -e '.marked_complete | index("TEST-A01")' > /dev/null 2>&1; then
  echo "  PASS: happy path"
else
  echo "  FAIL: happy path"
  FAILURES=$((FAILURES + 1))
fi
echo ""

# --- Fixture 2: not_found ---
echo "--- Fixture 2: not_found ---"
# Fresh REQUIREMENTS.md without TEST-B99
cat > "$TESTDIR/.planning/REQUIREMENTS.md" << 'REQEOF'
# Requirements: Watermark — Test

## Test Requirements

### Test Category

- [ ] **TEST-A01**: Test requirement one

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| TEST-A01 | Phase 99 | Pending |

**Coverage:**
- Test requirements: 1 total
- Mapped to phases: 1
REQEOF

RESULT2=$(cd "$TESTDIR" && gsd-sdk query requirements mark-complete TEST-B99 2>&1)
echo "  Result: $RESULT2"
if echo "$RESULT2" | jq -e '.not_found | length > 0' > /dev/null 2>&1; then
  echo "  PASS: not_found detected"
else
  echo "  FAIL: not_found not detected"
  FAILURES=$((FAILURES + 1))
fi

# Verify not_found did not mutate REQUIREMENTS.md
if echo "$RESULT2" | jq -e '.marked_complete | length == 0' > /dev/null 2>&1; then
  echo "  PASS: not_found did not mark anything"
else
  echo "  FAIL: not_found incorrectly marked items"
  FAILURES=$((FAILURES + 1))
fi

# Verify REQUIREMENTS.md is unmutated (TEST-B99 not introduced)
if grep -q 'TEST-B99' "$TESTDIR/.planning/REQUIREMENTS.md"; then
  echo "  FAIL: not_found mutated REQUIREMENTS.md"
  FAILURES=$((FAILURES + 1))
else
  echo "  PASS: not_found did not mutate REQUIREMENTS.md"
fi

# Verify original content still present
if grep -q '\[ \] \*\*TEST-A01\*\*' "$TESTDIR/.planning/REQUIREMENTS.md"; then
  echo "  PASS: original checkbox unmutated"
else
  echo "  FAIL: original checkbox was modified"
  FAILURES=$((FAILURES + 1))
fi
echo ""

# --- Fixture 3: already_complete / idempotency ---
echo "--- Fixture 3: already_complete ---"
# Fresh REQUIREMENTS.md with TEST-A01 already checked
cat > "$TESTDIR/.planning/REQUIREMENTS.md" << 'REQEOF'
# Requirements: Watermark — Test

## Test Requirements

### Test Category

- [x] **TEST-A01**: Already complete requirement

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| TEST-A01 | Phase 99 | Complete |

**Coverage:**
- Test requirements: 1 total
- Mapped to phases: 1
REQEOF

RESULT3=$(cd "$TESTDIR" && gsd-sdk query requirements mark-complete TEST-A01 2>&1)
echo "  Result: $RESULT3"
if echo "$RESULT3" | jq -e '.already_complete | index("TEST-A01")' > /dev/null 2>&1; then
  echo "  PASS: already_complete idempotent"
else
  echo "  FAIL: already_complete not detected"
  FAILURES=$((FAILURES + 1))
fi

if echo "$RESULT3" | jq -e '.marked_complete | length == 0' > /dev/null 2>&1; then
  echo "  PASS: already_complete did not re-mark"
else
  echo "  FAIL: already_complete incorrectly marked items"
  FAILURES=$((FAILURES + 1))
fi

if echo "$RESULT3" | jq -e '.not_found | length == 0' > /dev/null 2>&1; then
  echo "  PASS: already_complete no not_found"
else
  echo "  FAIL: already_complete returned not_found"
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
