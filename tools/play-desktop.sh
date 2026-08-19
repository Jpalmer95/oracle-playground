#!/usr/bin/env bash
# Desktop hangar (no SteamVR). Forces --xr-mode off so OpenXR does not steal the session.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-$(command -v godot || true)}"
if [[ -z "$GODOT" ]]; then
  echo "godot not on PATH" >&2
  exit 1
fi
exec "$GODOT" --path "$ROOT/godot" --xr-mode off "$@"
