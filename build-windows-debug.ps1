# Builds the Rust GDExtension in debug mode.
# Run this (or the release variant) before opening the project in Godot —
# without engine.dll there is no simulation and every screen shows a warning.
#
#   powershell -ExecutionPolicy Bypass -File .\build-windows-debug.ps1
#
# Prerequisite: the MSVC linker. If cargo reports "linker `link.exe` not found",
# install the C++ build tools:
#
#   winget install --id Microsoft.VisualStudio.2022.BuildTools `
#       --override "--wait --quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

Push-Location $root
try {
    cargo build --workspace
    if ($LASTEXITCODE -ne 0) { throw "cargo build failed" }

    $dll = Join-Path $root "target\debug\engine.dll"
    if (-not (Test-Path $dll)) { throw "expected $dll to exist after the build" }
    Write-Host "Built $dll" -ForegroundColor Green
    Write-Host "Open amerobe/project.godot in Godot and press Play." -ForegroundColor Green
}
finally {
    Pop-Location
}
