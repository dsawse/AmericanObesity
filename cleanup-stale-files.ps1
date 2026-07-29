# Removes leftovers from the pre-rewrite prototype. Nothing in the current
# project references any of these. Run with -WhatIf first if you want to see
# the list without deleting anything:
#
#   powershell -ExecutionPolicy Bypass -File .\cleanup-stale-files.ps1 -WhatIf

[CmdletBinding(SupportsShouldProcess = $true)]
param()

$root = Split-Path -Parent $MyInvocation.MyCommand.Path

$targets = @(
    "amerobe\evolution.gd"              # moved to Scripts/evolution.gd
    "amerobe\arena.gd.uid"              # orphan .uid, no matching script
    "amerobe\clickbutt.gd.uid"          # orphan .uid, no matching script
    "amerobe\Scripts\clickbutt.gd"      # superseded by Scripts/food_button.gd
    "amerobe\Scripts\tier_2.gd"         # tiers are handled by arena.gd now
    "amerobe\Scenes\tier_2.tscn"

    # .import stubs whose source PNG was never committed. Godot logs an error
    # for each one on startup; placeholder_art.gd covers the missing textures.
    "amerobe\art\soda_can_64x64.png.import"
    "amerobe\art\soda_can_64x64_flash.png.import"
    "amerobe\art\start_screen.png.import"
    "amerobe\art\nikacado_overweight_comp.png.import"
    "amerobe\art\nikacado_obese_comp_nbg.png.import"
)

foreach ($relative in $targets) {
    $path = Join-Path $root $relative
    if (Test-Path $path) {
        if ($PSCmdlet.ShouldProcess($path, "Remove")) {
            Remove-Item -LiteralPath $path -Force
            Write-Host "removed $relative"
        }
    }
}

# Editor scratch files, matched by pattern rather than by name.
Get-ChildItem -Path (Join-Path $root "amerobe") -Filter "*.tmp" -File |
    ForEach-Object {
        if ($PSCmdlet.ShouldProcess($_.FullName, "Remove")) {
            Remove-Item -LiteralPath $_.FullName -Force
            Write-Host "removed amerobe\$($_.Name)"
        }
    }

Write-Host "Done." -ForegroundColor Green
