#requires -Version 5.1
<#
.SYNOPSIS
  Publishes IdlePulse.exe (Release, self-contained, single-file) and builds the
  Inno Setup installer.

.DESCRIPTION
  Output: installer\dist\IdlePulse-Setup-<version>.exe

.NOTES
  Requires:
    - .NET 10 SDK (resolved from PATH or DOTNET environment variable)
    - Inno Setup 6.x (ISCC.exe). Searched in common locations or via $env:ISCC.
#>

param(
    [string]$Configuration = 'Release',
    [switch]$SkipPublish
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

# 1. Locate dotnet — prefer the SDK install at E:\SDKs\dotnet because the system
# C:\Program Files\dotnet on this machine is runtime-only.
$dotnet = $null
$dotnetCandidates = @(
    $env:DOTNET,
    'E:\SDKs\dotnet\dotnet.exe',
    (Get-Command dotnet -ErrorAction SilentlyContinue).Source
) | Where-Object { $_ -and (Test-Path $_) }

# Pick the first candidate whose folder actually contains an SDK.
foreach ($cand in $dotnetCandidates) {
    $sdkDir = Join-Path (Split-Path $cand) 'sdk'
    if ((Test-Path $sdkDir) -and (Get-ChildItem $sdkDir -Directory | Select-Object -First 1)) {
        $dotnet = $cand
        break
    }
}
if (-not $dotnet) { throw 'dotnet SDK not found. Install .NET 10 SDK or set $env:DOTNET.' }

# 2. Locate ISCC.exe
$candidates = @(
    $env:ISCC,
    'E:\Tools\Inno Setup 7\ISCC.exe',
    'E:\Tools\Inno Setup 6\ISCC.exe',
    'E:\SDKs\InnoSetup\ISCC.exe',
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe'
) | Where-Object { $_ -and (Test-Path $_) }
$iscc = $candidates | Select-Object -First 1
if (-not $iscc) {
    throw "ISCC.exe not found. Install Inno Setup 6.x or set `$env:ISCC."
}

Write-Host "dotnet: $dotnet"
Write-Host "iscc:   $iscc"

# 3. Publish the app
if (-not $SkipPublish) {
    Write-Host "`n=== Publishing IdlePulse ($Configuration) ==="

    # Stop any running instance so the publish doesn't fail with file-locks.
    Get-Process IdlePulse -ErrorAction SilentlyContinue | Stop-Process -Force

    & $dotnet publish IdlePulse.csproj -c $Configuration -o publish | Write-Host
    if ($LASTEXITCODE -ne 0) { throw "Publish failed (exit $LASTEXITCODE)" }
}

if (-not (Test-Path 'publish\IdlePulse.exe')) {
    throw 'publish\IdlePulse.exe missing. Run without -SkipPublish first.'
}

# 4. Compile installer
Write-Host "`n=== Building installer ==="
$null = New-Item -ItemType Directory -Path 'installer\dist' -Force

& $iscc /Qp 'installer\IdlePulse.iss' | Write-Host
if ($LASTEXITCODE -ne 0) { throw "ISCC failed (exit $LASTEXITCODE)" }

# 5. Report
$out = Get-ChildItem 'installer\dist\IdlePulse-Setup-*.exe' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($out) {
    $sizeMb = [Math]::Round($out.Length / 1MB, 1)
    Write-Host "`nInstaller: $($out.FullName) ($sizeMb MB)"
} else {
    Write-Host "`n(installer\dist is empty after build - check ISCC output above)"
}
