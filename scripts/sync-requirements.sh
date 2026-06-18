#!/usr/bin/env bash
# Source: D-04 pipeline specification from CONTEXT.md
# Recurrence guard: extracts requirements-completed from a SUMMARY frontmatter,
# delegates mutation to gsd-sdk query requirements mark-complete, and exits
# non-zero when any not_found IDs are returned.
set -euo pipefail

# --- Argument validation (D-02) ---
if [ $# -ne 1 ]; then
  echo "ERROR: Exactly one argument required (SUMMARY path)" >&2
  echo "Usage: $0 <path-to-SUMMARY.md>" >&2
  exit 2
fi
SUMMARY_PATH="$1"
if [ ! -f "$SUMMARY_PATH" ]; then
  echo "ERROR: SUMMARY not found: $SUMMARY_PATH" >&2
  exit 2
fi

# --- Step 1: Extract requirement IDs from SUMMARY frontmatter ---
IDS_JSON=$(gsd-sdk query frontmatter get "$SUMMARY_PATH" --pick requirements-completed 2>/dev/null)
if [ -z "$IDS_JSON" ] || [ "$IDS_JSON" = "null" ]; then
  echo "No requirements-completed found in SUMMARY frontmatter" >&2
  exit 0  # Not an error — plan may not have delivered new requirements
fi

# --- Step 2: Parse JSON array → comma-joined string ---
# Primary: jq (verified present on target: jq-1.7.1-apple)
if command -v jq &>/dev/null; then
  COMMA_IDS=$(echo "$IDS_JSON" | jq -r '.[]' 2>/dev/null | paste -sd, -)
else
  # Fallback: node (if jq unavailable)
  COMMA_IDS=$(echo "$IDS_JSON" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync(0,'utf8')).join(','))" 2>/dev/null)
fi

if [ -z "$COMMA_IDS" ]; then
  echo "requirements-completed array is empty" >&2
  exit 0
fi

# --- Step 3: Mark requirements complete ---
# Delegates to gsd-sdk query requirements mark-complete (milestone.cjs).
# mark-complete returns JSON with marked_complete, already_complete, not_found arrays.
# CRITICAL: mark-complete exits 0 even when not_found is non-empty (Pitfall #1).
# The script MUST parse the JSON response, NOT rely on exit code.
RESULT=$(gsd-sdk query requirements mark-complete "$COMMA_IDS" 2>&1)
echo "$RESULT"

# --- Step 4: Check for not_found (exit non-zero per D-09) ---
NOT_FOUND_COUNT=$(echo "$RESULT" | jq -r '.not_found | length' 2>/dev/null)
if [ "${NOT_FOUND_COUNT:-0}" -gt 0 ]; then
  echo "BLOCKER: ${NOT_FOUND_COUNT} requirement ID(s) not found in REQUIREMENTS.md" >&2
  echo "$RESULT" | jq -r '.not_found[]' 2>/dev/null >&2
  exit 1
fi

exit 0
