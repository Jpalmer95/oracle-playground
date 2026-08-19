#!/usr/bin/env bash
# Start Oracle Playground against the active OpenXR runtime (SteamVR).
# Put the Quest on Steam Link first so SteamVR is already streaming.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-$(command -v godot || true)}"
if [[ -z "$GODOT" ]]; then
  echo "godot not on PATH" >&2
  exit 1
fi
if [[ ! -f /usr/share/openxr/1/active_runtime.json && ! -f "$HOME/.config/openxr/1/active_runtime.json" ]]; then
  echo "No OpenXR runtime registered. SteamVR should own /usr/share/openxr/1/active_runtime.json" >&2
  exit 1
fi
echo "OpenXR runtime: SteamVR (this machine)"
echo "Headset must already be in SteamVR (Steam Link standing room), then this attaches."
export ORACLE_XR=1
# --xr-mode on forces the OpenXR Vulkan path at engine start.
# Runtime initialize() after a desktop boot cannot retrofit that.
exec "$GODOT" --path "$ROOT/godot" --xr-mode on "$@"
