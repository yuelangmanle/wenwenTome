Param(
  [switch]$SkipCopy,
  [string]$TargetPlatform = "android-arm64"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

$androidCommon = Join-Path $projectRoot "tools\android_dev_common.ps1"
if (-not (Test-Path $androidCommon)) {
  throw "Android env helper not found: $androidCommon"
}
. $androidCommon

$ctx = Get-ProjectAndroidContext -ScriptPath $PSCommandPath
Set-ProjectAndroidEnvironment -Context $ctx

flutter build apk --release --target-platform $TargetPlatform
if ($LASTEXITCODE -ne 0) {
  throw "flutter build apk failed with exit code $LASTEXITCODE"
}

if ($SkipCopy) {
  return
}

$pubspecPath = Join-Path $projectRoot "pubspec.yaml"
$pubspec = Get-Content -Raw -Encoding UTF8 $pubspecPath
$match = [regex]::Match($pubspec, "(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$")
if (-not $match.Success) {
  throw "Cannot parse version from pubspec.yaml"
}
$version = $match.Groups[1].Value

$releaseDir = Join-Path $projectRoot "releases\$version"
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

$apkSource = Join-Path $projectRoot "build\app\outputs\flutter-apk\app-release.apk"
$apkTarget = Join-Path $releaseDir ("wenwen_tome_android_{0}.apk" -f $version)
Copy-Item -Force $apkSource $apkTarget

Write-Host "APK copied to $apkTarget"
