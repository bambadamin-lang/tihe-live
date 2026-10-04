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
  breaks the feature that calls it. So is a missing import of a DLL listed in
  $unusedOnWindows, which Flutter bundles but no Windows code opens. The script fails instead
  if anything in the bundle imports such a DLL, because then it does load at start-up.

  With -BundleVcRuntime, Visual C++ runtime DLLs the bundle needs are first copied in from
  System32 (app-local deployment, which Microsoft permits), until nothing more is needed.

  DLLs in $removeIfUnimported are deleted from the bundle first when nothing in it imports
  them, and the build fails if something does.

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

# FFI plugin DLLs that Flutter bundles because their package lists Windows, but that nothing
# on Windows opens. Each entry says why.
$unusedOnWindows = @{
  'dartjni.dll' = 'package:jni, used only by path_provider_android. Its CMake means to delay-load jvm.dll but sets the flag on an undefined target, so a build machine with a JDK links jvm.dll directly.'
}

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

# Shipped by a prebuilt archive but imported by nothing in the bundle. Each entry says why it
# has to go rather than ship.
$removeIfUnimported = @{
  'zlib.dll' = 'media_kit_libs_windows_video copies it from its prebuilt ANGLE archive, as a debug build that needs the Visual C++ debug runtime (ucrtbased.dll, vcruntime140d.dll), which no student PC has and which may not be redistributed. ANGLE links zlib statically.'
}
$needs = Get-Needs
foreach ($dll in $removeIfUnimported.Keys) {
  if (-not (Test-Bundled $dll)) { continue }
  if ($needs.ContainsKey($dll)) {
    throw "$dll is imported by $(($needs[$dll].By | Sort-Object -Unique) -join ', '): it cannot be removed, so bundle a release build of it instead"
  }
  Remove-Item (Join-Path $bundleDir $dll)
  Write-Host "Removed $dll, which nothing imports ($($removeIfUnimported[$dll]))"
}

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
foreach ($dll in $unusedOnWindows.Keys) {
  if ($needs.ContainsKey($dll)) {
    $errors += "$dll is imported by $(($needs[$dll].By | Sort-Object -Unique) -join ', '), so it loads at start-up: remove it from `$unusedOnWindows and bundle what it needs"
  }
}
foreach ($dll in $needs.Keys | Sort-Object) {
  $need = $needs[$dll]
  $importers = @($need.By | Sort-Object -Unique)
  $line = "$dll  <- $($importers -join ', ')"
  if ((Test-Bundled $dll) -or $dll -match '^(api|ext)-ms-win-') { continue }
  $onlyUnused = -not ($importers | Where-Object { -not $unusedOnWindows.ContainsKey($_.ToLowerInvariant()) })
  if ($dll -notmatch $redistributable -and (Test-Path (Join-Path $system32 $dll))) {
    $windows += $line
  } elseif ($onlyUnused) {
    $why = ($importers | ForEach-Object { $unusedOnWindows[$_.ToLowerInvariant()] }) -join ' '
    $warnings += "$line (never opened on Windows: $why)"
  } elseif ($need.Delay) {
    $warnings += "$line (delay-loaded: only the feature using it would fail)"
  } else {
    $errors += "Loaded at start-up but neither bundled nor part of Windows: $line"
  }
}

Write-Host "Windows DLLs the app relies on ($($windows.Count)):"
$windows | ForEach-Object { Write-Host "  $_" }
foreach ($w in $warnings) {
  Write-Host "::warning::Not bundled, but never loaded at start-up: $w"
}
if ($errors) {
  foreach ($e in $errors) {
    Write-Host "::error::$e"
  }
  exit 1
}
Write-Host "Every start-up dependency is bundled or part of Windows."
