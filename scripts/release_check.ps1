Param(
  [switch]$SkipAnalyze,
  [switch]$SkipTest,
  [switch]$SkipAndroid,
  [switch]$SkipWindows
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

function Ensure-Dir($path) {
  New-Item -ItemType Directory -Force -Path $path | Out-Null
}

# Keep caches/temp inside the project folder by default.
$pubCache = Join-Path $projectRoot ".pub-cache"
$tempRoot = Join-Path $projectRoot "tmp\\release-check"
Ensure-Dir $pubCache
Ensure-Dir $tempRoot
$env:PUB_CACHE = $pubCache
$env:TEMP = $tempRoot
$env:TMP = $tempRoot

function Parse-PubspecVersion {
  $pubspecPath = Join-Path $projectRoot "pubspec.yaml"
  if (-not (Test-Path $pubspecPath)) { throw "pubspec.yaml not found: $pubspecPath" }
  $content = Get-Content -Raw -Encoding UTF8 $pubspecPath
  $m = [regex]::Match($content, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$')
  if (-not $m.Success) { throw "Cannot parse version from pubspec.yaml" }
  return [pscustomobject]@{
    Version = $m.Groups[1].Value
    BuildNumber = [int]$m.Groups[2].Value
  }
}

function Parse-VersionJson {
  $path = Join-Path $projectRoot "version.json"
  if (-not (Test-Path $path)) { throw "version.json not found: $path" }
  $json = Get-Content -Raw -Encoding UTF8 $path | ConvertFrom-Json
  return $json
}

function Parse-SetupIssVersion {
  $path = Join-Path $projectRoot "setup.iss"
  if (-not (Test-Path $path)) { throw "setup.iss not found: $path" }
  $text = Get-Content -Raw -Encoding UTF8 $path
  $m = [regex]::Match($text, '#define\s+MyAppVersion\s+"(?<ver>[0-9]+\.[0-9]+\.[0-9]+)"')
  if (-not $m.Success) { throw "Cannot parse MyAppVersion from setup.iss" }
  return $m.Groups["ver"].Value
}

function Assert-Equal($label, $expected, $actual) {
  if ($expected -ne $actual) {
    throw "$label mismatch. Expected '$expected' but got '$actual'."
  }
}

function Assert-FileContains($path, $pattern, $label) {
  if (-not (Test-Path $path)) { throw "$label not found: $path" }
  $text = Get-Content -Raw -Encoding UTF8 $path
  if ($text -notmatch $pattern) {
    throw "$label does not contain expected pattern: $pattern"
  }
}

$pubspec = Parse-PubspecVersion
$versionJson = Parse-VersionJson
$issVersion = Parse-SetupIssVersion

Assert-Equal "version.json version" $pubspec.Version $versionJson.version
Assert-Equal "version.json buildNumber" $pubspec.BuildNumber ([int]$versionJson.buildNumber)
Assert-Equal "setup.iss version" $pubspec.Version $issVersion

$setupIss = Join-Path $projectRoot "setup.iss"
$escapedVersion = [regex]::Escape($pubspec.Version)
$setupOutputDirPattern = '(?m)^OutputDir=releases\\' + $escapedVersion + '\s*$'
$setupOutputBasePattern =
  '(?m)^OutputBaseFilename=wenwen_tome_windows_' + $escapedVersion + '_setup\s*$'
Assert-FileContains $setupIss $setupOutputDirPattern "setup.iss OutputDir"
Assert-FileContains $setupIss $setupOutputBasePattern "setup.iss OutputBaseFilename"

$platformAndroid = "$($pubspec.Version)+$($pubspec.BuildNumber)"
Assert-Equal "version.json platform.android" $platformAndroid $versionJson.platform.android
Assert-Equal "version.json platform.windows" $platformAndroid $versionJson.platform.windows

$changelog = Join-Path $projectRoot "CHANGELOG.md"
$changelogPattern = '(?m)^## \[' + $escapedVersion + '\]'
Assert-FileContains $changelog $changelogPattern "CHANGELOG.md"

$releaseDir = Join-Path $projectRoot ("releases\\{0}" -f $pubspec.Version)
Ensure-Dir $releaseDir
$releaseNotes = Join-Path $releaseDir "release_notes.md"
if (-not (Test-Path $releaseNotes)) {
  Write-Host "WARN: release_notes.md missing: $releaseNotes"
}

if (-not $SkipAnalyze) {
  flutter analyze --no-fatal-infos
  if ($LASTEXITCODE -ne 0) { throw "flutter analyze failed with exit code $LASTEXITCODE" }
}

if (-not $SkipTest) {
  flutter test
  if ($LASTEXITCODE -ne 0) { throw "flutter test failed with exit code $LASTEXITCODE" }
}

if (-not $SkipAndroid) {
  powershell -ExecutionPolicy Bypass -File scripts\\build_android.ps1
  if ($LASTEXITCODE -ne 0) { throw "Android build failed with exit code $LASTEXITCODE" }
}

if (-not $SkipWindows) {
  powershell -ExecutionPolicy Bypass -File scripts\\build_win.ps1
  if ($LASTEXITCODE -ne 0) { throw "Windows build failed with exit code $LASTEXITCODE" }
}

Write-Host "Release check OK: $platformAndroid"
