Param(
  [string]$InstallRoot = "E:\\tools\\gh",
  [string]$TempRoot = ""
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($TempRoot)) {
  $TempRoot = Join-Path $projectRoot "tmp\\gh-install"
}

New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null

$release = Invoke-RestMethod `
  -Headers @{ "User-Agent" = "codex" } `
  -Uri "https://api.github.com/repos/cli/cli/releases/latest"
$asset = $release.assets |
  Where-Object { $_.name -like "*_windows_amd64.zip" } |
  Select-Object -First 1

if (-not $asset) {
  throw "Could not find the GitHub CLI Windows amd64 zip asset."
}

$zipPath = Join-Path $TempRoot $asset.name
Invoke-WebRequest `
  -Headers @{ "User-Agent" = "codex" } `
  -Uri $asset.browser_download_url `
  -OutFile $zipPath

$extractRoot = Join-Path $TempRoot "extract"
if (Test-Path $extractRoot) {
  Remove-Item -Recurse -Force $extractRoot
}
Expand-Archive -Path $zipPath -DestinationPath $extractRoot -Force

Get-ChildItem $InstallRoot -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
Copy-Item -Path (Join-Path $extractRoot "*") -Destination $InstallRoot -Recurse -Force

$ghBin = if (Test-Path (Join-Path $InstallRoot "bin\\gh.exe")) {
  Join-Path $InstallRoot "bin"
} elseif (Test-Path (Join-Path $InstallRoot "gh.exe")) {
  $InstallRoot
} else {
  throw "gh.exe was not found after installation."
}
$env:PATH = "$ghBin;$env:PATH"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ([string]::IsNullOrWhiteSpace($userPath)) {
  $newUserPath = $ghBin
} elseif (($userPath -split ";") -notcontains $ghBin) {
  $newUserPath = "$ghBin;$userPath"
} else {
  $newUserPath = $userPath
}
[Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")

& (Join-Path $ghBin "gh.exe") --version
