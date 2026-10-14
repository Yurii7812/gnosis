#Requires -Version 5.1
# Gnosis Windows installer entry point.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File install\install.ps1
#
# IMPORTANT: Keep this file ASCII-only so Windows PowerShell 5.1 reads it
# correctly even when it assumes the system code page instead of UTF-8.
# The supported Windows installation uses WSL2 + Ubuntu + WezTerm.
[CmdletBinding()]
param(
    [switch]$Yes,
    [switch]$NoSystem,
    [switch]$NoApp,
    [switch]$SkipInstall,
    [switch]$NoShortcut
)

$ErrorActionPreference = 'Stop'
$installer = Join-Path $PSScriptRoot 'install-windows.ps1'
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    Write-Error 'Missing install/install-windows.ps1. Update your Gnosis checkout.'
    exit 1
}
if ($Yes) {
    Write-Host 'For safety, WSL/Ubuntu and WezTerm installation still require explicit confirmation.'
}
if ($NoApp) {
    Write-Host 'Electron is not installed by the WSL2/WezTerm installer.'
}
$skip = [bool]($NoSystem -or $SkipInstall)
try {
    & $installer -SkipInstall:$skip -NoShortcut:$NoShortcut
    if (-not $?) {
        exit 1
    }
} catch {
    Write-Error $_
    exit 1
}
