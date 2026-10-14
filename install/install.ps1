#Requires -Version 5.1
# Gnosis Windows installer. ASCII only for Windows PowerShell 5.1.
#
# Default: complete native Windows GUI desktop app with one-click shortcut.
# Optional: -WSL installs the separate Ubuntu/WezTerm terminal edition.
#
# powershell -ExecutionPolicy Bypass -File install\install.ps1
[CmdletBinding()]
param(
  [switch]$NoSystem,
  [switch]$NoShortcut,
  [switch]$WSL,
  [switch]$Yes,
  [switch]$NoApp,
  [switch]$SkipInstall
)
$ErrorActionPreference = 'Stop'
if ($NoApp -and -not $WSL) {
  throw 'A native desktop install requires the Electron app. Use -WSL for terminal-only installation.'
}
$script = if ($WSL) { 'install-windows.ps1' } else { 'install-native.ps1' }
$installer = Join-Path $PSScriptRoot $script
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
  throw ('The Windows installer is missing: ' + $installer)
}
$skip = [bool]($NoSystem -or $SkipInstall)
try {
  # The native app is installed by default. WSL system changes remain opt-in.
  if ($WSL) {
    & $installer -NoShortcut:$NoShortcut -SkipInstall:$skip
  } else {
    & $installer -NoShortcut:$NoShortcut -NoSystem:$skip
  }
  if (-not $?) { throw 'Gnosis installer returned a failure.' }
} catch {
  Write-Error $_
  exit 1
}
