#!/usr/bin/env bash
# Headless test suite for the Godot side of project-platinum.
#
#   tools/run_tests.sh
#   tools/run_tests.sh -- --filter=save
#   tools/run_tests.sh -- --require-data        # pendings become failures
#
# Exits 0 only when every check passed. Anything else is a failure.
#
# Two things this script exists to handle, both verified in
# docs/research/godot-architecture.md 6.3:
#   * `--import` must run first, or `class_name` globals and imported PNGs do not
#     exist yet.
#   * `--import` exits 0 even when it logs fatal-looking errors, so its exit
#     status is worthless as a gate. We gate on the class cache existing instead.
set -uo pipefail

GODOT="${GODOT:-C:/Users/James/Documents/GitHub/Godot_v4.7.2-stable_win64_console.exe}"
PROJ="$(cd "$(dirname "$0")/.." && pwd)"   # project.godot lives at the repo root

if [ ! -x "$GODOT" ] && [ ! -f "$GODOT" ]; then
  echo "godot binary not found: $GODOT" >&2
  echo "set GODOT=/path/to/Godot_v4.7.2-stable_win64_console.exe" >&2
  exit 1
fi

echo "== import: refreshing the class cache =="
"$GODOT" --headless --path "$PROJ" --import 2>&1 \
  | grep -Ei "^(ERROR|SCRIPT ERROR|WARNING)" || true

if [ ! -f "$PROJ/.godot/global_script_class_cache.cfg" ]; then
  echo "import did not produce .godot/global_script_class_cache.cfg" >&2
  exit 1
fi

echo
echo "== tests =="
set -o pipefail
"$GODOT" --headless --path "$PROJ" --script res://tests/run_tests.gd "$@" 2>&1 \
  | grep -v "were leaked at exit\|RIDs of type\|RID allocations of type"
status=${PIPESTATUS[0]}

echo
if [ "$status" -eq 0 ]; then
  echo "TESTS PASSED (exit 0)"
else
  echo "TESTS FAILED (exit $status)" >&2
fi
exit "$status"
