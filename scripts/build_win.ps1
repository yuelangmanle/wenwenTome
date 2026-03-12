Param(
  [switch]$SkipInstaller
)

$ErrorActionPreference = "Stop"

function Get-SubstMap {
  $map = @{}
  $lines = cmd /c subst
  foreach ($line in $lines) {
    if ($line -match '^(?<drive>[A-Z]):\\: => (?<path>.+)$') {
      $map[$matches.drive] = $matches.path
    }
  }
  return $map
}

function Resolve-WorkspaceRoot {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot
  )

  if ($ProjectRoot -notmatch '\s') {
    return $ProjectRoot
  }

  $projectParent = Split-Path -Parent $ProjectRoot
  $projectLeaf = Split-Path -Leaf $ProjectRoot

  $substMap = Get-SubstMap
  foreach ($entry in $substMap.GetEnumerator()) {
    if ($entry.Value -eq $projectParent) {
      return (Join-Path "$($entry.Key):\" $projectLeaf)
    }
  }

  foreach ($drive in @('W', 'X', 'Y', 'Z')) {
    if (-not (Get-PSDrive -Name $drive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
      cmd /c "subst $drive`: `"$projectParent`"" | Out-Null
      return (Join-Path "${drive}:\" $projectLeaf)
    }
  }

  throw "No free drive letter available for SUBST mapping."
}

$projectRootPhysical = Split-Path -Parent $PSScriptRoot
$projectRoot = Resolve-WorkspaceRoot -ProjectRoot $projectRootPhysical
Set-Location $projectRoot

$pubCache = Join-Path $projectRoot ".pub-cache"
$tempRoot = Join-Path $projectRoot "tmp\\windows-tools"
New-Item -ItemType Directory -Force -Path $pubCache | Out-Null
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$env:PUB_CACHE = $pubCache
$env:TEMP = $tempRoot
$env:TMP = $tempRoot

$toolsDir = Join-Path $projectRoot "tools"
$nugetExe = Join-Path $toolsDir "nuget.exe"
if (-not (Test-Path $nugetExe)) {
  Write-Host "Downloading nuget.exe to $nugetExe"
  New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
  curl.exe -L "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" -o $nugetExe | Out-Null
}

$cacheRoot = Join-Path $projectRoot ".cache\nuget"
New-Item -ItemType Directory -Force -Path (Join-Path $cacheRoot "packages") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $cacheRoot "v3-cache") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $cacheRoot "plugins-cache") | Out-Null

$env:PATH = "$toolsDir;$env:PATH"
$env:NUGET_PACKAGES = Join-Path $cacheRoot "packages"
$env:NUGET_HTTP_CACHE_PATH = Join-Path $cacheRoot "v3-cache"
$env:NUGET_PLUGINS_CACHE_PATH = Join-Path $cacheRoot "plugins-cache"

$nugetConfig = Join-Path $projectRoot "NuGet.Config"
if (-not (Test-Path $nugetConfig)) {
  throw "NuGet.Config not found: $nugetConfig"
}

$validator = Join-Path $projectRoot "scripts\validate_inno_lang.py"
if (-not (Test-Path $validator)) {
  throw "Installer language validator not found: $validator"
}

function Ensure-NuGetPackage {
  param(
    [Parameter(Mandatory = $true)][string]$PackageId,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$ExpectedPath
  )

  if (Test-Path $ExpectedPath) {
    return
  }

  New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
  & $nugetExe install $PackageId `
    -Version $Version `
    -OutputDirectory $OutputDirectory `
    -ConfigFile $nugetConfig `
    -DirectDownload `
    -DependencyVersion Ignore `
    -NonInteractive | Out-Null

  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $ExpectedPath)) {
    throw "Failed to install $PackageId $Version into $OutputDirectory"
  }
}

function Ensure-PackageAliasDirectory {
  param(
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$AliasDirectory,
    [Parameter(Mandatory = $true)][string]$ExpectedPath
  )

  if (Test-Path $ExpectedPath) {
    return
  }

  if (Test-Path $AliasDirectory) {
    cmd /c rmdir /s /q "$AliasDirectory"
  }

  cmd /c xcopy "$SourceDirectory\*" "$AliasDirectory\" /E /I /Y | Out-Null

  if (-not (Test-Path $ExpectedPath)) {
    throw "Failed to materialize package alias directory: $AliasDirectory"
  }
}

Ensure-NuGetPackage `
  -PackageId "Microsoft.Windows.CppWinRT" `
  -Version "2.0.210806.1" `
  -OutputDirectory (Join-Path $projectRoot "build\windows\x64\packages") `
  -ExpectedPath (Join-Path $projectRoot "build\windows\x64\packages\Microsoft.Windows.CppWinRT.2.0.210806.1\bin\cppwinrt.exe")

Ensure-PackageAliasDirectory `
  -SourceDirectory (Join-Path $projectRoot "build\windows\x64\packages\Microsoft.Windows.CppWinRT.2.0.210806.1") `
  -AliasDirectory (Join-Path $projectRoot "build\windows\x64\packages\Microsoft.Windows.CppWinRT") `
  -ExpectedPath (Join-Path $projectRoot "build\windows\x64\packages\Microsoft.Windows.CppWinRT\build\native\Microsoft.Windows.CppWinRT.props")

python $validator (Join-Path $projectRoot "tools\ChineseSimplified.isl")
if ($LASTEXITCODE -ne 0) {
  throw "Installer language validation failed with exit code $LASTEXITCODE"
}

function Ensure-PdfiumBinary {
  param(
    [Parameter(Mandatory = $true)][string]$CMakeBinaryDir,
    [Parameter(Mandatory = $true)][string]$ReleaseTag,
    [Parameter(Mandatory = $true)][string]$Abi
  )

  $releaseDir = Join-Path $CMakeBinaryDir ("pdfium\\{0}" -f $ReleaseTag)
  $dllPath = Join-Path $releaseDir "bin\\pdfium.dll"
  $includePath = Join-Path $releaseDir "include"
  if ((Test-Path $dllPath) -and (Test-Path $includePath)) {
    return
  }

  New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

  $archiveBase = "pdfium-win-$Abi"
  $archivePath = Join-Path $releaseDir ("{0}.tgz" -f $archiveBase)
  $url = "https://github.com/bblanchon/pdfium-binaries/releases/download/$ReleaseTag/$archiveBase.tgz"

  $needsDownload = $true
  if (Test-Path $archivePath) {
    try {
      $len = (Get-Item $archivePath).Length
      if ($len -gt 1024) {
        $needsDownload = $false
      }
    } catch {
      $needsDownload = $true
    }
  }

  if ($needsDownload) {
    Write-Host "Downloading PDFium prebuilt archive: $url"
    $tmpArchive = Join-Path $env:TEMP ("{0}.tgz" -f [guid]::NewGuid().ToString("n"))
    curl.exe -L --fail $url -o $tmpArchive
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to download PDFium archive from $url (exit code $LASTEXITCODE)"
    }
    Move-Item -Force $tmpArchive $archivePath
  }

  Write-Host "Extracting PDFium: $archivePath"
  tar -xzf $archivePath -C $releaseDir
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to extract PDFium archive: $archivePath (exit code $LASTEXITCODE)"
  }

  if (-not (Test-Path $dllPath)) {
    throw "PDFium DLL missing after extract: $dllPath"
  }
  if (-not (Test-Path $includePath)) {
    throw "PDFium headers missing after extract: $includePath"
  }
}

$cmakeBinaryDir = Join-Path $projectRoot "build\\windows\\x64"
Ensure-PdfiumBinary -CMakeBinaryDir $cmakeBinaryDir -ReleaseTag "chromium%2F7202" -Abi "x64"

flutter build windows --release
if ($LASTEXITCODE -ne 0) {
  throw "flutter build windows failed with exit code $LASTEXITCODE"
}

$releaseRunnerDir = Join-Path $projectRoot "build\windows\x64\runner\Release"
$distDir = Join-Path $projectRoot "build\windows\x64\dist"
if (Test-Path $distDir) {
  cmd /c rmdir /s /q "$distDir"
}
cmd /c xcopy "$releaseRunnerDir\*" "$distDir\" /E /I /Y | Out-Null

if ($SkipInstaller) {
  return
}

$iscc = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc)) {
  throw "Inno Setup compiler not found: $iscc"
}

& $iscc (Join-Path $projectRoot "setup.iss")
if ($LASTEXITCODE -ne 0) {
  throw "Inno Setup compilation failed with exit code $LASTEXITCODE"
}
