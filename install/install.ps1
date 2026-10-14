#Requires -Version 5.1
# Gnosis terminal installer on Windows. ASCII-only for PowerShell 5.1.
# Default: WSL2 + Ubuntu + WezTerm + desktop shortcut that launches Vim.
# Electron is optional, never the default.
#
# powershell -ExecutionPolicy Bypass -File install\install.ps1
[CmdletBinding()]
param(
  [switch]$NoSystem,
  [switch]$NoShortcut,
  [switch]$WSL,
  [switch]$NativeApp,
  [switch]$Yes,
  [switch]$NoApp,
  [switch]$SkipInstall,
  [switch]$Resume,
  [string]$Ref = '',
  [string]$Distro = ''
)
$ErrorActionPreference = 'Stop'
if ($NativeApp -and $NoApp) {
  throw 'Conflicting flags: -NativeApp and -NoApp.'
}
$installer = Join-Path $PSScriptRoot $(if ($NativeApp) { 'install-native.ps1' } else { 'install-windows.ps1' })
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
  throw ('Installer is missing: ' + $installer)
}
$skip = [bool]($NoSystem -or $SkipInstall)
try {
  if ($NativeApp) {
    & $installer -NoShortcut:$NoShortcut -NoSystem:$skip
  } else {
    & $installer -NoShortcut:$NoShortcut -SkipInstall:$skip -Resume:$Resume -Yes:$Yes -Ref $Ref -Distro $Distro
  }
  if (-not $?) { throw 'Gnosis setup did not complete.' }
} catch {
  Write-Error $_
  exit 1
}
