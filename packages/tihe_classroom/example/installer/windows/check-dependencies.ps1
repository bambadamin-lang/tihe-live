<#
.SYNOPSIS
  Fails the build if the Windows bundle loads a DLL that a clean Windows 10 (2004+) PC lacks,
  so Setup.exe never needs a separate runtime install.

.DESCRIPTION
  Reads the import tables of every .exe and .dll in the bundle with dumpbin. Each DLL loaded at
  start-up must be:
    - in the bundle's top folder, where the Windows loader looks first;
    - a Windows API set (api-ms-win-*, ext-ms-win-*), which is part of Windows itself; or
    - a Windows DLL: in System32 and not one of the redistributables that only appear there
      once another product installs them (Visual C++, DirectX SDK, Vulkan, OpenCL...).
  Delay-loaded DLLs open on first use, not at start-up, so a missing one is a warning: it only
  breaks the feature that calls it. The jni package delay-loads jvm.dll for Android-only
  code, for example.

  With -BundleVcRuntime, Visual C++ runtime DLLs the bundle needs are first copied in from
  System32 (app-local deployment, which Microsoft permits), until nothing more is needed.

.EXAMPLE
  ./check-dependencies.ps1 -Bundle ..\..\build\windows\x64\runner\Release -BundleVcRuntime
#>
param(
  [Parameter(Mandatory)] [string] $Bundle,
  [switch] $BundleVcRuntime,
  # Found through vswhere when not given.
  [string] $Dumpbin
)
$ErrorActionPreference = 'Stop'

# In System32 on a developer PC or CI runner, but not on a fresh Windows.
$redistributable = '^(msvcp\d+.*|vcruntime\d+.*|vcomp\d+.*|concrt\d+|vccorlib\d+|mfc\d+.*|msvcr\d+.*|ucrtbased|d3dx.*|xinput1_[0-3]|xaudio2_[0-7]|vulkan-1|opencl|nvcuda|libegl|libglesv2|jvm)\.dll$'
$vcRuntime = '^(msvcp140(_\d|_atomic_wait|_codecvt_ids)?|vcruntime140(_1)?|concrt140|vccorlib140)\.dll$'

if (-not $Dumpbin) {
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  $Dumpbin = & $vswhere -latest -products * -find 'VC\Tools\MSVC\**\bin\Hostx64\x64\dumpbin.exe' |
    Select-Object -First 1
}
if (-not $Dumpbin) { throw 'dumpbin.exe not found: install the Visual Studio C++ build tools.' }

$bundleDir = (Resolve-Path $Bundle).Path
$system32 = Join-Path $env:WINDIR 'System32'

# dumpbin prints two indented lists of DLL names: "Image has the following dependencies:"
# and "Image has the following delay load dependencies:".
function Get-Imports([string] $path) {
  $out = & $Dumpbin /nologo /dependents $path
  if ($LASTEXITCODE -ne 0) { throw "dumpbin failed on $path" }
  $section = $null
  foreach ($line in $out) {
    $text = $line.Trim()
    if ($text -like '*delay load dependencies:*') { $section = 'delay'; continue }
    if ($text -like '*following dependencies:*') { $section = 'load'; continue }
    if ($text -eq 'Summary') { break }
    if ($section -and $text -match '^[^\s\\/:]+\.dll$') {
      [pscustomobject]@{ Dll = $text.ToLowerInvariant(); Delay = ($section -eq 'delay') }
    }
  }
}

function Get-Needs {
  $needs = @{}
  foreach ($bin in Get-ChildItem $bundleDir -Recurse -Include *.exe, *.dll -File) {
    foreach ($import in Get-Imports $bin.FullName) {
      if (-not $needs.ContainsKey($import.Dll)) {
        $needs[$import.Dll] = [pscustomobject]@{ By = [System.Collections.Generic.List[string]]::new(); Delay = $true }
      }
      $needs[$import.Dll].By.Add($bin.Name)
      # One ordinary import is enough to make it a start-up dependency.
      if (-not $import.Delay) { $needs[$import.Dll].Delay = $false }
    }
  }
  $needs
}

function Test-Bundled([string] $dll) { Test-Path (Join-Path $bundleDir $dll) }

do {
  $needs = Get-Needs
  $copied = $false
  if ($BundleVcRuntime) {
    foreach ($dll in @($needs.Keys)) {
      if ($dll -match $vcRuntime -and -not (Test-Bundled $dll)) {
        Copy-Item (Join-Path $system32 $dll) $bundleDir
        Write-Host "Bundled $dll (needed by $($needs[$dll].By -join ', '))"
        $copied = $true
      }
    }
  }
} while ($copied)

$errors = @(); $warnings = @(); $windows = @()
foreach ($dll in $needs.Keys | Sort-Object) {
  $need = $needs[$dll]
  $line = "$dll  <- $(($need.By | Sort-Object -Unique) -join ', ')"
  if ((Test-Bundled $dll) -or $dll -match '^(api|ext)-ms-win-') { continue }
  if ($dll -notmatch $redistributable -and (Test-Path (Join-Path $system32 $dll))) {
    $windows += $line
  } elseif ($need.Delay) {
    $warnings += $line
  } else {
    $errors += $line
  }
}

Write-Host "Windows DLLs the app relies on ($($windows.Count)):"
$windows | ForEach-Object { Write-Host "  $_" }
foreach ($w in $warnings) {
  Write-Host "::warning::Delay-loaded and not bundled (only the feature using it would fail): $w"
}
if ($errors) {
  foreach ($e in $errors) {
    Write-Host "::error::Loaded at start-up but neither bundled nor part of Windows: $e"
  }
  exit 1
}
Write-Host "Every start-up dependency is bundled or part of Windows."
