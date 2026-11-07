# Copies the mod into a game folder with REFramework: mod\reframework\autorun\DD2DamageMeter.lua and every file of
# mod\reframework\autorun\DD2DamageMeter\ go to <GameDir>\reframework\autorun\ (same names, existing ones are
# overwritten, nothing else there is deleted). reframework\data is never touched, so
# reframework\data\DD2DamageMeter\settings.json (and debug.log) stay as they are. -RemoveProbe also deletes exactly
# dd2dm_probe.lua and dd2dm_recon.lua from <GameDir>\reframework\autorun\.
# The game folder must have REFramework: <GameDir>\dinput8.dll, or the <GameDir>\reframework folder.
param(
    [Parameter(Mandatory = $true)][string]$GameDir,
    [switch]$RemoveProbe
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $GameDir -PathType Container)) { throw "No folder '$GameDir'. Nothing done." }
$GameDir = (Resolve-Path -LiteralPath $GameDir).Path
$ref = Join-Path $GameDir 'reframework'
$dll = Join-Path $GameDir 'dinput8.dll'
if (-not (Test-Path -LiteralPath $dll -PathType Leaf) -and -not (Test-Path -LiteralPath $ref -PathType Container)) {
    throw "No REFramework in '$GameDir' (neither dinput8.dll nor a reframework folder). Nothing done."
}

$srcRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\mod\reframework\autorun')).Path
$entry = Join-Path $srcRoot 'DD2DamageMeter.lua'
$srcDir = Join-Path $srcRoot 'DD2DamageMeter'
if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { throw "Missing $entry. Nothing done." }
if (-not (Test-Path -LiteralPath $srcDir -PathType Container)) { throw "Missing $srcDir. Nothing done." }
$files = @(Get-ChildItem -LiteralPath $srcDir -Recurse -File | Sort-Object FullName)
if ($files.Count -eq 0) { throw "No files in $srcDir. Nothing done." }

$autorun = Join-Path $ref 'autorun'
if (-not (Test-Path -LiteralPath $autorun -PathType Container)) {
    # also creates reframework\ when the game has not been started since installing the dll
    New-Item -ItemType Directory -Path $autorun -Force | Out-Null
    "Created $autorun"
}

$dst = Join-Path $autorun 'DD2DamageMeter.lua'
Copy-Item -LiteralPath $entry -Destination $dst -Force
"Copied DD2DamageMeter.lua -> $dst ($((Get-Item -LiteralPath $dst).Length) bytes)"
$dstDir = Join-Path $autorun 'DD2DamageMeter'
foreach ($f in $files) {
    $rel = $f.FullName.Substring($srcDir.Length).TrimStart('\')
    $dst = Join-Path $dstDir $rel
    $parent = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
    "Copied DD2DamageMeter\$rel -> $dst ($((Get-Item -LiteralPath $dst).Length) bytes)"
}
"Copied $($files.Count + 1) files."

# files of an earlier version that the mod no longer has: listed, not deleted (they are never loaded)
$known = @{}
foreach ($f in $files) { $known[$f.FullName.Substring($srcDir.Length).TrimStart('\').ToLowerInvariant()] = $true }
foreach ($f in @(Get-ChildItem -LiteralPath $dstDir -Recurse -File)) {
    $rel = $f.FullName.Substring($dstDir.Length).TrimStart('\')
    if (-not $known.ContainsKey($rel.ToLowerInvariant())) { "Not part of the mod (left in place): $($f.FullName)" }
}

$settings = Join-Path $ref 'data\DD2DamageMeter\settings.json'
if (Test-Path -LiteralPath $settings -PathType Leaf) { "Kept $settings" } else { "No settings yet: $settings" }

if ($RemoveProbe) {
    foreach ($n in @('dd2dm_probe.lua', 'dd2dm_recon.lua')) {
        $probe = Join-Path $autorun $n
        if (Test-Path -LiteralPath $probe -PathType Leaf) {
            Remove-Item -LiteralPath $probe -Force
            "Removed $probe"
        } else {
            "Not there: $probe"
        }
    }
}
