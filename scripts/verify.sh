#!/usr/bin/env bash
set -euo pipefail

game_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
summer="${SUMMER_BIN:-godot}"

if [[ "$summer" == */* ]]; then
  if [[ ! -x "$summer" ]]; then
    echo "SUMMER_BIN is not executable: $summer" >&2
    exit 1
  fi
elif ! command -v "$summer" >/dev/null 2>&1; then
  echo "Set SUMMER_BIN to a Summer Engine or Godot executable." >&2
  exit 1
fi

tests=(
  verify_world.gd
  verify_movement.gd
  verify_requested_regressions.gd
  verify_vehicle_customization.gd
  verify_high_speed_steering.gd
  verify_mobile_controls.gd
  verify_weather.gd
)

for test_script in "${tests[@]}"; do
  if [[ "$test_script" == "verify_world.gd" ]]; then
    # This test reads back MultiMesh transforms. Summer's headless dummy renderer
    # intentionally returns identity transforms, so it needs a real renderer.
    "$summer" --path "$game_root" --script "res://tests/$test_script"
  else
    "$summer" --headless --path "$game_root" --script "res://tests/$test_script"
  fi
done
