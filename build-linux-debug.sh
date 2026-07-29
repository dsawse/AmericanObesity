#!/usr/bin/env bash
# Builds the Rust GDExtension in debug mode. Run this before opening the
# project in Godot — without libengine.so there is no simulation.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$root"

cargo build --workspace

so="$root/target/debug/libengine.so"
[[ -f "$so" ]] || { echo "expected $so to exist after the build" >&2; exit 1; }
echo "Built $so"
echo "Open amerobe/project.godot in Godot and press Play."
