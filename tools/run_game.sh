#!/usr/bin/env bash
# Run the game.
#
#   tools/run_game.sh              # the title screen: CAMPAIGN or CUSTOM BATTLE
#   tools/run_game.sh --custom     # straight into Custom Battle mode
#   tools/run_game.sh --campaign   # straight into Twinleaf Town
#   tools/run_game.sh -- <args>    # anything else, passed to Godot verbatim
#
# `godot --path <dir>` RUNS a project; `godot -e --path <dir>` edits it. Launching
# the binary with no arguments at all opens the Project Manager, and picking the
# project there opens the EDITOR -- which is the usual reason "it opened Godot
# instead of the game". From inside the editor, F5 runs the main scene.
#
# In PowerShell a quoted path is a string, not a command, so the same call needs
# the call operator:  & "C:/.../Godot_....exe" --path .
# This script exists so that does not have to be remembered.
set -uo pipefail

GODOT="${GODOT:-C:/Users/James/Documents/GitHub/Godot_v4.7.2-stable_win64_console.exe}"
PROJ="$(cd "$(dirname "$0")/.." && pwd)"   # project.godot lives at the repo root

if [ ! -x "$GODOT" ] && [ ! -f "$GODOT" ]; then
  echo "godot binary not found: $GODOT" >&2
  echo "set GODOT=/path/to/Godot_v4.7.2-stable_win64_console.exe" >&2
  exit 1
fi

SCENE=""
case "${1:-}" in
  --custom)   SCENE="res://scenes/CustomBattle.tscn"; shift ;;
  --campaign) SCENE="res://scenes/Boot.tscn"; shift ;;
  --title|"") shift 2>/dev/null || true ;;
  --)         shift ;;
esac

# A scene passed positionally is run INSTEAD of run/main_scene. Skipping the title
# is only a convenience: both scenes are self-contained roots, which is the same
# property that lets the test suite instance either one on its own.
if [ -n "$SCENE" ]; then
  echo "== running $SCENE =="
  exec "$GODOT" --path "$PROJ" "$SCENE" "$@"
fi

echo "== running the title screen (w/s move, enter select) =="
exec "$GODOT" --path "$PROJ" "$@"
