Param(
  [Parameter(Mandatory = $true)]
  [string]$Repo,

  [Parameter(Mandatory = $true)]
  [string]$StorePassword,

  [Parameter(Mandatory = $true)]
  [string]$KeyPassword,

  [Parameter(Mandatory = $true)]
  [string]$KeyAlias,

  [string]$KeystorePath = ".keys\\release.jks"
)

$ErrorActionPreference = "Stop"

$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($gh) {
  $ghCommand = $gh.Source
} elseif (Test-Path "E:\tools\gh\bin\gh.exe") {
  $ghCommand = "E:\tools\gh\bin\gh.exe"
} else {
  throw "GitHub CLI (gh) is not installed or not on PATH."
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$resolvedKeystorePath = Join-Path $projectRoot $KeystorePath
if (-not (Test-Path $resolvedKeystorePath)) {
  throw "Keystore not found: $resolvedKeystorePath"
}

$keystoreBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($resolvedKeystorePath))

$secretMap = @{
  ANDROID_KEYSTORE_BASE64   = $keystoreBase64
  ANDROID_KEYSTORE_PASSWORD = $StorePassword
  ANDROID_KEY_PASSWORD      = $KeyPassword
  ANDROID_KEY_ALIAS         = $KeyAlias
}

foreach ($entry in $secretMap.GetEnumerator()) {
  & $ghCommand secret set $entry.Key --repo $Repo --body $entry.Value
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to set GitHub secret: $($entry.Key)"
  }
}

Write-Host "GitHub Android secrets updated for $Repo"
