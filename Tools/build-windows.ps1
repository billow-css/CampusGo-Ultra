[CmdletBinding()]
param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') { throw 'Run this script on Windows x86_64.' }
if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne 'X64') {
    throw 'This script packages Windows x86_64.'
}
$repoDir = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoDir 'dist\windows-x86_64' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
foreach ($command in @('node', 'npm.cmd', 'rustc', 'cargo')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Missing $command. See Docs/Windows.md for Rust MSVC and C++ Build Tools prerequisites."
    }
}
function Invoke-Checked([string]$File, [string[]]$Arguments) {
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$File failed with exit code $LASTEXITCODE" }
}

Push-Location (Join-Path $repoDir 'Desktop')
try {
    $env:CARGO_TARGET_DIR = Join-Path (Get-Location) 'src-tauri\target'
    $target = 'x86_64-pc-windows-msvc'
    Invoke-Checked 'npm.cmd' @('ci')
    Invoke-Checked 'npm.cmd' @('run', 'build')
    Invoke-Checked 'npm.cmd' @('test')
    Invoke-Checked 'cargo' @('test', '--release', '--locked', '--features', 'tauri/custom-protocol', '--manifest-path', 'src-tauri/Cargo.toml', '--target', $target)
    Invoke-Checked 'npm.cmd' @('run', 'tauri', '--', 'build', '--ci', '--target', $target, '--bundles', 'nsis', '--', '--locked')
    $version = (Get-Content package.json -Raw | ConvertFrom-Json).version
    $bundle = Join-Path $env:CARGO_TARGET_DIR "$target\release\bundle\nsis"
    $installers = @(Get-ChildItem -LiteralPath $bundle -Filter '*-setup.exe')
    if ($installers.Count -ne 1) { throw "Expected one installer, found $($installers.Count) in $bundle" }
    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    $name = "CampusGo-Ultra_${version}_windows-x86_64-setup.exe"
    Copy-Item -LiteralPath $installers[0].FullName -Destination (Join-Path $OutputDirectory $name)
    foreach ($file in @('LICENSE', 'NOTICE')) {
        Copy-Item -LiteralPath (Join-Path $repoDir $file) -Destination $OutputDirectory
    }
    $hash = (Get-FileHash -LiteralPath (Join-Path $OutputDirectory $name) -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'SHA256SUMS.txt'), "$hash  $name`n")
    Write-Output "Windows installer ready: $(Join-Path $OutputDirectory $name)"
}
finally { Pop-Location }
