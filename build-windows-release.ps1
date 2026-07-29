# Builds the Rust GDExtension in release mode and exports a Windows build.
#
# NOTE: amerobe/export_presets.cfg currently only defines a "Linux" preset, so
# the export step below is skipped until you add a "Windows Desktop" preset in
# Godot (Project > Export > Add). The engine.dll this produces is all you need
# to run from the editor either way.
#
#   powershell -ExecutionPolicy Bypass -File .\build-windows-release.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

Push-Location $root
try {
    cargo build --workspace --release
    if ($LASTEXITCODE -ne 0) { throw "cargo build failed" }

    $dll = Join-Path $root "target\release\engine.dll"
    if (-not (Test-Path $dll)) { throw "expected $dll to exist after the build" }
    Write-Host "Built $dll" -ForegroundColor Green

    $presets = Get-Content (Join-Path $root "amerobe\export_presets.cfg") -Raw `
        -ErrorAction SilentlyContinue
    $hasPreset = $presets -and ($presets -match '(?m)^name="Windows Desktop"$')

    if ((Get-Command godot -ErrorAction SilentlyContinue) -and $hasPreset) {
        Push-Location (Join-Path $root "amerobe")
        try {
            New-Item -ItemType Directory -Force -Path "..\target\export" | Out-Null
            godot --headless --export-release "Windows Desktop" `
                "..\target\export\american-obesity.exe"
        }
        finally { Pop-Location }
    }
    else {
        Write-Host ("Skipping export: needs godot on PATH and a " +
            "'Windows Desktop' preset in amerobe/export_presets.cfg.") `
            -ForegroundColor Yellow
    }
}
finally {
    Pop-Location
}
