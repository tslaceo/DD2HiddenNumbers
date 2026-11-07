# Builds the release archive out\HiddenNumbers-<version>.zip, to be extracted into the game folder. "Hidden Numbers" is
# the name players see; the files inside keep the name DD2DamageMeter.
# The version comes from the entry file (the line local VERSION = "x.y.z" in
# mod\reframework\autorun\DD2DamageMeter.lua); CHANGELOG.md must have a "## x.y.z" section for it. README.md must not
# hold the placeholder <GITHUB_URL> (its links to the GitHub repository, written before the repository existed).
# The archive holds exactly: reframework/autorun/DD2DamageMeter.lua, every file of
# reframework/autorun/DD2DamageMeter/, and README.md and LICENSE inside that folder too, so that nothing lands
# next to the game's exe. out\ is git-ignored.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\package.ps1
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
$autorun = Join-Path $repoRoot "mod\reframework\autorun"
$entry = Join-Path $autorun "DD2DamageMeter.lua"
$tree = Join-Path $autorun "DD2DamageMeter"

if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { throw "Missing $entry" }
if (-not (Test-Path -LiteralPath $tree -PathType Container)) { throw "Missing $tree" }

$entryText = Get-Content -LiteralPath $entry -Raw -Encoding UTF8
$found = [regex]::Match($entryText, '(?m)^local VERSION = "(\d+\.\d+\.\d+)"\s*$')
if (-not $found.Success) { throw "DD2DamageMeter.lua has no line: local VERSION = ""x.y.z""" }
$version = $found.Groups[1].Value

$changelog = Get-Content -LiteralPath (Join-Path $repoRoot "CHANGELOG.md") -Raw -Encoding UTF8
if ($changelog -notmatch ('(?m)^## ' + [regex]::Escape($version) + '\s*$')) {
    throw "CHANGELOG.md has no section '## $version'"
}
$settings = Get-Content -LiteralPath (Join-Path $tree "settings.lua") -Raw -Encoding UTF8
if ($settings -notmatch '(?m)^\s*debug = false,') { throw "settings.lua: debug must default to false" }
if ($settings -notmatch '(?m)^\s*history_file = false,') { throw "settings.lua: history_file must default to false" }

# mod\reframework\autorun must hold only the entry file and the folder: no probe, no leftovers.
$top = @(Get-ChildItem -LiteralPath $autorun | ForEach-Object { $_.Name } | Sort-Object)
$wantTop = @("DD2DamageMeter", "DD2DamageMeter.lua")
if (Compare-Object $wantTop $top) { throw "mod\reframework\autorun must hold exactly $($wantTop -join ', '), has: $($top -join ', ')" }
$files = @(Get-ChildItem -LiteralPath $tree -Recurse -File)
if ($files.Count -eq 0) { throw "No files in $tree" }
foreach ($f in $files) {
    if ($f.Extension -ne ".lua") { throw "Not a .lua file in the mod folder: $($f.FullName)" }
}
foreach ($name in @("README.md", "LICENSE")) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $name) -PathType Leaf)) { throw "Missing $name" }
}
$readme = Get-Content -LiteralPath (Join-Path $repoRoot "README.md") -Raw -Encoding UTF8
if ($readme.Contains("<GITHUB_URL>")) {
    throw ("README.md still holds the placeholder <GITHUB_URL> (the links to the GitHub repository's Issues). " +
        "Replace it with the repository's URL, such as https://github.com/<owner>/<repo>, then build again.")
}

# What goes into the archive: entry name (forward slashes; Compress-Archive in Windows PowerShell writes
# backslashes) -> file.
$items = @(
    @{ Name = "reframework/autorun/DD2DamageMeter.lua"; Path = $entry },
    @{ Name = "reframework/autorun/DD2DamageMeter/README.md"; Path = (Join-Path $repoRoot "README.md") },
    @{ Name = "reframework/autorun/DD2DamageMeter/LICENSE"; Path = (Join-Path $repoRoot "LICENSE") }
)
foreach ($f in $files) {
    $rel = $f.FullName.Substring($tree.Length + 1).Replace('\', '/')
    $items += @{ Name = "reframework/autorun/DD2DamageMeter/$rel"; Path = $f.FullName }
}
$items = @($items | Sort-Object { $_.Name })

$outDir = Join-Path $repoRoot "out"
New-Item -ItemType Directory -Force $outDir | Out-Null
$zip = Join-Path $outDir "HiddenNumbers-$version.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force -Confirm:$false }

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($item in $items) {
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $item.Path, $item.Name, [System.IO.Compression.CompressionLevel]::Optimal)
    }
} finally {
    $archive.Dispose()
}

# Read the archive back: it must hold exactly the planned entries, all under reframework/autorun/.
$check = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
    $got = @($check.Entries | ForEach-Object { $_.FullName } | Sort-Object)
    $listing = @($check.Entries | ForEach-Object { "{0,9}  {1}" -f $_.Length, $_.FullName })
} finally {
    $check.Dispose()
}
$want = @($items | ForEach-Object { $_.Name } | Sort-Object)
if (Compare-Object $want $got) { throw "The archive does not hold exactly the planned files" }
foreach ($name in $got) {
    if (-not $name.StartsWith("reframework/autorun/DD2DamageMeter")) { throw "Entry outside the mod's files: $name" }
}

$listing
Write-Output "Packaged $zip ($($got.Count) files)"
