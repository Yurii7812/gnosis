#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$entry = Join-Path $root 'install\install.ps1'
$terminal = Join-Path $root 'install\install-windows.ps1'
$native = Join-Path $root 'install\install-native.ps1'

# PS 5.1 cannot safely parse non-ASCII characters in UTF-8 files without a BOM.
foreach ($file in @($entry,$terminal,$native)) {
  $bytes = [IO.File]::ReadAllBytes($file)
  if (@($bytes | Where-Object { $_ -gt 127 }).Count -ne 0) {
    throw ('Non-ASCII Windows PowerShell installer: ' + $file)
  }
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile(
    $file,[ref]$tokens,[ref]$errors
  ) | Out-Null
  if ($errors.Count -gt 0) {
    throw ('PowerShell 5.1 parse error: ' + $file + ' - ' + ($errors | Out-String))
  }
}
Write-Host 'OK: all Windows install scripts parse in PowerShell 5.1'

# Terminal must really be configured and verified before launcher completion.
$termSource = [IO.File]::ReadAllText($terminal)
foreach ($check in @('WezTerm','Ubuntu','Gnosis.lnk','Start-Gnosis.ps1',
    'test -x "$HOME/.local/bin/gnosis"','Gnosis is available from the Desktop',
    'CreateShortcut','-WindowStyle Hidden','no-such-never')) {
  if ($check -eq 'no-such-never') { continue }
  if (-not $termSource.Contains($check)) {
    throw ('Missing terminal desktop setup check: ' + $check)
  }
}
Write-Host 'OK: shortcut follows verified terminal Gnosis installation'

# Exercise the *same* encoding function against a real Bash on Windows CI.
# This catches CRLF, quotes and multi-line shell programs breaking when
# Windows PowerShell 5.1 passes them as arguments to a Linux shell.
$bash = @(
  (Join-Path $env:ProgramFiles 'Git\bin\bash.exe'),
  (Join-Path $env:ProgramFiles 'Git\usr\bin\bash.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bash) { throw 'Git Bash is required for the WSL transport regression' }
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
  $terminal,[ref]$tokens,[ref]$errors
)
$fn = $ast.Find({
  param($node)
  $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
  $node.Name -eq 'ConvertTo-WslBashCommand'
},$true)
if (-not $fn) { throw 'Missing WSL script transport helper' }
Invoke-Expression $fn.Extent.Text

$crlf = ([string][char]13 + [string][char]10)
$sample = @(
  'set -eu',
  'value="hello world"',
  'if test "$value" = "hello world"; then',
  '  printf "WSL_TRANSPORT_OK:%s\n" "$value"',
  'fi'
) -join $crlf
$line = ConvertTo-WslBashCommand $sample
if ($line.Contains([string][char]10) -or $line.Contains([string][char]13)) {
  throw 'Multiline script was not converted to a single CLI argument'
}
$output = & $bash -c $line
if ($LASTEXITCODE -ne 0 -or (($output -join '') -ne 'WSL_TRANSPORT_OK:hello world')) {
  throw ('Base64 Bash transport did not preserve CRLF, quotes and conditions: ' + ($output -join ' '))
}
Write-Host 'OK: PowerShell 5.1 to Bash transport preserves CRLF and quotations'

# Validate the real installation and verification scripts without invoking
# apt-get, git clone or touching the user's WSL distribution.
foreach ($name in @('bootstrap','verify')) {
  $begin = '

$nativeSource = [IO.File]::ReadAllText($native)
if (-not $nativeSource.Contains('$pyArgs = @()')) {
  throw 'Optional native Python helper must not add a null argv element'
}
Write-Host 'OK: native Python empty-argument regression guard'

# Exercise documented entrypoint in isolation. Never call winget, WSL, npm.
$tmp = Join-Path $env:TEMP ('gnosis-terminal-installer-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
  Copy-Item -LiteralPath $entry -Destination (Join-Path $tmp 'install.ps1')
  @'
param([switch]$SkipInstall,[switch]$NoShortcut)
if (-not $SkipInstall -or -not $NoShortcut) { throw 'Terminal flags not forwarded' }
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'terminal-invoked'), 'yes')
'@ | Set-Content -LiteralPath (Join-Path $tmp 'install-windows.ps1') -Encoding Ascii
  @'
param([switch]$NoSystem,[switch]$NoShortcut)
if (-not $NoSystem -or -not $NoShortcut) { throw 'Native flags not forwarded' }
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'native-invoked'), 'yes')
'@ | Set-Content -LiteralPath (Join-Path $tmp 'install-native.ps1') -Encoding Ascii
  & (Join-Path $tmp 'install.ps1') -NoSystem -NoShortcut
  if (-not (Test-Path (Join-Path $tmp 'terminal-invoked'))) {
    throw 'Default installer did not select terminal Gnosis'
  }
  & (Join-Path $tmp 'install.ps1') -NativeApp -NoSystem -NoShortcut
  if (-not (Test-Path (Join-Path $tmp 'native-invoked'))) {
    throw 'Optional Electron installer was not explicitly selected'
  }
  Write-Host 'OK: default=terminal; Electron is opt-in'
} finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
 + $name + ' = @' + [char]39
  $start = $termSource.IndexOf($begin)
  if ($start -lt 0) { throw ('Missing WSL script: ' + $name) }
  $start = $termSource.IndexOf([string][char]10,$start) + 1
  $end = $termSource.IndexOf(([string][char]10 + [char]39 + '@'),$start)
  if ($end -lt $start) { throw ('Unterminated WSL script: ' + $name) }
  $body = $termSource.Substring($start,$end-$start)
  $check = (ConvertTo-WslBashCommand $body) -replace ' \| bash

$nativeSource = [IO.File]::ReadAllText($native)
if (-not $nativeSource.Contains('$pyArgs = @()')) {
  throw 'Optional native Python helper must not add a null argv element'
}
Write-Host 'OK: native Python empty-argument regression guard'

# Exercise documented entrypoint in isolation. Never call winget, WSL, npm.
$tmp = Join-Path $env:TEMP ('gnosis-terminal-installer-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
  Copy-Item -LiteralPath $entry -Destination (Join-Path $tmp 'install.ps1')
  @'
param([switch]$SkipInstall,[switch]$NoShortcut)
if (-not $SkipInstall -or -not $NoShortcut) { throw 'Terminal flags not forwarded' }
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'terminal-invoked'), 'yes')
'@ | Set-Content -LiteralPath (Join-Path $tmp 'install-windows.ps1') -Encoding Ascii
  @'
param([switch]$NoSystem,[switch]$NoShortcut)
if (-not $NoSystem -or -not $NoShortcut) { throw 'Native flags not forwarded' }
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'native-invoked'), 'yes')
'@ | Set-Content -LiteralPath (Join-Path $tmp 'install-native.ps1') -Encoding Ascii
  & (Join-Path $tmp 'install.ps1') -NoSystem -NoShortcut
  if (-not (Test-Path (Join-Path $tmp 'terminal-invoked'))) {
    throw 'Default installer did not select terminal Gnosis'
  }
  & (Join-Path $tmp 'install.ps1') -NativeApp -NoSystem -NoShortcut
  if (-not (Test-Path (Join-Path $tmp 'native-invoked'))) {
    throw 'Optional Electron installer was not explicitly selected'
  }
  Write-Host 'OK: default=terminal; Electron is opt-in'
} finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
,' | bash -n'
  & $bash -c $check
  if ($LASTEXITCODE -ne 0) { throw ('Bash syntax failed: ' + $name) }
}
Write-Host 'OK: both real WSL scripts survive command transport and Bash parsing'


$nativeSource = [IO.File]::ReadAllText($native)
if (-not $nativeSource.Contains('$pyArgs = @()')) {
  throw 'Optional native Python helper must not add a null argv element'
}
Write-Host 'OK: native Python empty-argument regression guard'

# Exercise documented entrypoint in isolation. Never call winget, WSL, npm.
$tmp = Join-Path $env:TEMP ('gnosis-terminal-installer-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
  Copy-Item -LiteralPath $entry -Destination (Join-Path $tmp 'install.ps1')
  @'
param([switch]$SkipInstall,[switch]$NoShortcut)
if (-not $SkipInstall -or -not $NoShortcut) { throw 'Terminal flags not forwarded' }
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'terminal-invoked'), 'yes')
'@ | Set-Content -LiteralPath (Join-Path $tmp 'install-windows.ps1') -Encoding Ascii
  @'
param([switch]$NoSystem,[switch]$NoShortcut)
if (-not $NoSystem -or -not $NoShortcut) { throw 'Native flags not forwarded' }
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'native-invoked'), 'yes')
'@ | Set-Content -LiteralPath (Join-Path $tmp 'install-native.ps1') -Encoding Ascii
  & (Join-Path $tmp 'install.ps1') -NoSystem -NoShortcut
  if (-not (Test-Path (Join-Path $tmp 'terminal-invoked'))) {
    throw 'Default installer did not select terminal Gnosis'
  }
  & (Join-Path $tmp 'install.ps1') -NativeApp -NoSystem -NoShortcut
  if (-not (Test-Path (Join-Path $tmp 'native-invoked'))) {
    throw 'Optional Electron installer was not explicitly selected'
  }
  Write-Host 'OK: default=terminal; Electron is opt-in'
} finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
