#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$entry = Join-Path $root 'install\install.ps1'
$native = Join-Path $root 'install\install-native.ps1'
$wsl = Join-Path $root 'install\install-windows.ps1'

foreach ($file in @($entry, $native, $wsl)) {
  $bytes = [System.IO.File]::ReadAllBytes($file)
  if (@($bytes | Where-Object { $_ -gt 127 }).Count -ne 0) {
    throw ('Windows PowerShell 5.1 installer has non-ASCII text: ' + $file)
  }
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile(
    $file,[ref]$tokens,[ref]$errors
  ) | Out-Null
  if ($errors.Count -gt 0) {
    throw ('PowerShell 5.1 parser error in ' + $file + ': ' + ($errors | Out-String))
  }
}
Write-Host 'OK: native, entrypoint, and WSL scripts parse in PowerShell 5.1'

$contents = [IO.File]::ReadAllText($native)
foreach ($contract in @('electron.exe','bundle.js','node-pty','Gnosis.lnk','Start-Gnosis.ps1','vimrc_gnosis','npm','rebuild:pty','GNOSIS_VIM','GNOSIS_VIMRC')) {
  if (-not $contents.Contains($contract)) {
    throw ('Native desktop installer omits required step: ' + $contract)
  }
}
Write-Host 'OK: native installer includes GUI build, terminal backend and shortcuts'

# Test the installer's external-command wrapper without installing packages.
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
  $native, [ref]$tokens, [ref]$errors
)
$fn = $ast.Find({
  param($node)
  $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Run'
}, $true)
if (-not $fn) { throw 'Missing native dependency runner' }
Invoke-Expression $fn.Extent.Text
Run (Join-Path $PSHOME 'powershell.exe') @('-NoProfile','-Command','exit 0') 'safe external command'
Write-Host 'OK: native installer can invoke external build tools and handle exit codes'


# Exercise the real documented entrypoint with simulated installers, without
# invoking winget, WSL, npm, or changing installed applications.
$tmp = Join-Path $env:TEMP ('gnosis-win-installer-test-' + [guid]::NewGuid().ToString('N'))
New-Item -Path $tmp -ItemType Directory -Force | Out-Null
try {
  Copy-Item -LiteralPath $entry -Destination (Join-Path $tmp 'install.ps1')
  @'
param([switch]$NoSystem,[switch]$NoShortcut)
if (-not $NoSystem -or -not $NoShortcut) { throw 'Native flags were not forwarded' }
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'native-invoked'), 'yes')
'@ | Set-Content -LiteralPath (Join-Path $tmp 'install-native.ps1') -Encoding Ascii
  @'
param([switch]$SkipInstall,[switch]$NoShortcut)
if (-not $SkipInstall -or -not $NoShortcut) { throw 'WSL flags were not forwarded' }
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'wsl-invoked'), 'yes')
'@ | Set-Content -LiteralPath (Join-Path $tmp 'install-windows.ps1') -Encoding Ascii
  & (Join-Path $tmp 'install.ps1') -NoSystem -NoShortcut
  if (-not (Test-Path (Join-Path $tmp 'native-invoked'))) {
    throw 'Default install did not launch native Electron setup'
  }
  & (Join-Path $tmp 'install.ps1') -WSL -NoSystem -NoShortcut
  if (-not (Test-Path (Join-Path $tmp 'wsl-invoked'))) {
    throw 'Explicit -WSL install did not launch WSL setup'
  }
  Write-Host 'OK: desktop GUI is default; WSL is explicitly optional'
} finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
