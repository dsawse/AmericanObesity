# Cross-compiles the Rust GDExtension for Android.
#
#   powershell -ExecutionPolicy Bypass -File .\build-android.ps1
#   powershell -ExecutionPolicy Bypass -File .\build-android.ps1 -Release
#   powershell -ExecutionPolicy Bypass -File .\build-android.ps1 -Abi arm64
#
# One-time setup (see docs/MOBILE.md for the long version):
#
#   rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
#   cargo install cargo-ndk
#   # Install the Android NDK via Android Studio, then set:
#   $env:ANDROID_NDK_HOME = "C:\Users\<you>\AppData\Local\Android\Sdk\ndk\<version>"

[CmdletBinding()]
param(
    [switch]$Release,
    # arm64 alone is enough for real devices. "all" adds arm32 and x86_64
    # (old phones and the emulator) at the cost of build time and APK size.
    [ValidateSet("arm64", "all")]
    [string]$Abi = "arm64"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Preflight -------------------------------------------------------------

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    throw "cargo not found. Install Rust from https://rustup.rs"
}

if (-not (Get-Command cargo-ndk -ErrorAction SilentlyContinue)) {
    throw "cargo-ndk not found. Run: cargo install cargo-ndk"
}

if (-not $env:ANDROID_NDK_HOME) {
    # cargo-ndk also accepts ANDROID_NDK_ROOT / NDK_HOME; only warn.
    if (-not $env:ANDROID_NDK_ROOT -and -not $env:NDK_HOME) {
        throw @"
ANDROID_NDK_HOME is not set and no fallback was found.
Install the NDK through Android Studio (SDK Manager > SDK Tools > NDK),
then set it for this session:

  `$env:ANDROID_NDK_HOME = "`$env:LOCALAPPDATA\Android\Sdk\ndk\<version>"

or permanently via System Properties > Environment Variables.
"@
    }
}

$targets = if ($Abi -eq "all") {
    @("arm64-v8a", "armeabi-v7a", "x86_64")
} else {
    @("arm64-v8a")
}

$profileArgs = @()
$profileDir = "debug"
if ($Release) {
    $profileArgs = @("--release")
    $profileDir = "release"
}

# --- Build -----------------------------------------------------------------

Push-Location $root
try {
    $targetArgs = @()
    foreach ($t in $targets) { $targetArgs += @("-t", $t) }

    Write-Host "Building for: $($targets -join ', ') ($profileDir)" -ForegroundColor Cyan

    # `--platform 24` matches Godot's Android minimum SDK. Bump it only if you
    # also raise min_sdk in the export preset.
    & cargo ndk @targetArgs --platform 24 build -p engine @profileArgs
    if ($LASTEXITCODE -ne 0) { throw "cargo ndk build failed" }

    # --- Verify the .so landed where engine.gdextension expects it ----------
    $tripleFor = @{
        "arm64-v8a"   = "aarch64-linux-android"
        "armeabi-v7a" = "armv7-linux-androideabi"
        "x86_64"      = "x86_64-linux-android"
    }

    foreach ($t in $targets) {
        $so = Join-Path $root "target\$($tripleFor[$t])\$profileDir\libengine.so"
        if (-not (Test-Path $so)) {
            throw "expected $so to exist after the build"
        }
        $sizeMb = [math]::Round((Get-Item $so).Length / 1MB, 1)
        Write-Host "  OK  $so  ($sizeMb MB)" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "Next: in Godot, Project > Export > Android > Export Project." -ForegroundColor Green
    if (-not $Release) {
        Write-Host "This was a debug build. Use -Release before publishing." -ForegroundColor Yellow
    }
}
finally {
    Pop-Location
}
