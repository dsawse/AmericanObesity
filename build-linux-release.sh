#!/usr/bin/env bash
# Builds the Rust GDExtension in release mode and exports a Linux build.
# The export step is skipped when `godot` is not on PATH; the .so it produces
# is all you need to run from the editor.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$root"

cargo build --workspace --release

so="$root/target/release/libengine.so"
[[ -f "$so" ]] || { echo "expected $so to exist after the build" >&2; exit 1; }
echo "Built $so"

if command -v godot >/dev/null 2>&1; then
	mkdir -p "$root/target/export"
	cd "$root/amerobe"
	godot --headless --export-release "Linux" "$root/target/export/american-obesity"
else
	echo "godot not found on PATH - skipping the export step."
fi
