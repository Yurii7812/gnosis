#Requires -Version 5.1
# Windows installer regression tests. Safe: never installs WSL/WezTerm, never touches the
# real Desktop, Start menu, %LOCALAPPDATA%\Gnosis or the user's RunOnce entries.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$files = @('install.ps1','install-windows.ps1','install-native.ps1','bootstrap.ps1') | ForEach-Object { Join-Path $root ('install\' + $_) }
$terminal = Join-Path $root 'install\install-windows.ps1'

# 1. ASCII-only + parses in this PowerShell (CI runs it in 5.1 and 7).
foreach ($file in $files) {
  $bytes = [IO.File]::ReadAllBytes($file)
  if (@($bytes | Where-Object { $_ -gt 127 }).Count -ne 0) { throw ('Non-ASCII Windows PowerShell installer: ' + $file) }
  $tokens = $null; $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors) | Out-Null
  if ($errors.Count -gt 0) { throw ('PowerShell parse error: ' + $file + ' - ' + ($errors | Out-String)) }
}
Write-Host 'OK: all Windows install scripts are ASCII and parse'

# 2. The Electron / GUI entry points must never be the shortcut target.
$src = [IO.File]::ReadAllText($terminal)
if ($src -match 'gnosis --(app|gui)') { throw 'install-windows.ps1 mentions gnosis --app/--gui' }
if ($src -notmatch 'gnosis --tui') { throw 'launcher must run gnosis --tui' }
Write-Host 'OK: launcher is gnosis --tui only'

# 3. Load the real functions (dot-source returns before running the installer).
$tmp = Join-Path $env:TEMP ('gnosis installer test ' + [guid]::NewGuid().ToString('N').Substring(0,8))
$oldLocal = $env:LOCALAPPDATA
New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'lad') | Out-Null
$env:LOCALAPPDATA = Join-Path $tmp 'lad'
try {
  . $terminal -ShortcutDir $tmp
  $script:StateDir = Join-Path $env:LOCALAPPDATA 'Gnosis'
  $script:StateFile = Join-Path $script:StateDir 'install-state.json'
  $script:LogFile = Join-Path $script:StateDir 'install.log'
  $script:RunOnceName = 'GnosisInstallResumeTest'

  # 3a. distribution selection (several distros, Debian default, versioned Ubuntu)
  $Distro = ''
  if ((Select-UbuntuDistro @('Debian','Ubuntu','Other')) -ne 'Ubuntu') { throw 'Ubuntu not selected among several distros' }
  if ((Select-UbuntuDistro @('Debian','Ubuntu-24.04')) -ne 'Ubuntu-24.04') { throw 'Versioned Ubuntu not selected' }
  if (Select-UbuntuDistro @('Debian')) { throw 'Debian must not be mistaken for Ubuntu' }
  Write-Host 'OK: distribution selection'

  # 3b. resume: state round trip, RunOnce registered once, then removed
  $Ref = 'v1.0'
  Set-State 'linux-setup' 'Ubuntu'
  $st = Get-State
  if ($st.phase -ne 'linux-setup' -or $st.distro -ne 'Ubuntu' -or $st.ref -ne 'v1.0') { throw 'State did not round-trip' }
  Register-Resume
  $rk = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
  $val = (Get-ItemProperty -Path $rk -Name $script:RunOnceName).$($script:RunOnceName)
  if ($val -notmatch '-Resume' -or $val -notmatch 'install-windows\.ps1' -or $val -notmatch 'v1\.0') { throw ('Bad RunOnce command: ' + $val) }
  if (-not (Test-Path -LiteralPath (Join-Path $script:StateDir 'installer\install\install-windows.ps1'))) { throw 'Installer copy for resume missing' }
  Clear-Resume
  if (Get-ItemProperty -Path $rk -Name $script:RunOnceName -ErrorAction SilentlyContinue) { throw 'RunOnce not cleared' }
  Write-Host 'OK: reboot-resume state and RunOnce register/clear'

  # 3c. launcher + shortcut in a path with spaces and Japanese characters
  $uni = Join-Path $tmp ('lad ' + [char]0x30c6 + [char]0x30b9 + [char]0x30c8)
  New-Item -ItemType Directory -Force -Path $uni | Out-Null
  $env:LOCALAPPDATA = $uni
  $script:StateDir = Join-Path $uni 'Gnosis'
  Install-Launcher 'Ubuntu' 'someone'
  $lnk = Join-Path $tmp 'Gnosis.lnk'
  $w = New-Object -ComObject WScript.Shell
  $l = $w.CreateShortcut($lnk)
  if ($l.TargetPath -notlike '*wscript.exe') { throw ('Shortcut target: ' + $l.TargetPath) }
  if ($l.Arguments -notlike '*Start-Gnosis.vbs*') { throw ('Shortcut args: ' + $l.Arguments) }
  if ($l.Arguments -match 'powershell') { throw 'Shortcut must not open a PowerShell window' }
  $vbs = [IO.File]::ReadAllText((Join-Path $script:StateDir 'Start-Gnosis.vbs'))
  if ($vbs -notmatch '-WindowStyle Hidden' -or $vbs -notmatch 'Start-Gnosis\.ps1') { throw 'VBS does not run the hidden launcher' }
  $ps1 = [IO.File]::ReadAllText((Join-Path $script:StateDir 'Start-Gnosis.ps1'))
  if ($ps1 -notmatch "distro = 'Ubuntu'" -or $ps1 -notmatch 'gnosis --tui' -or $ps1 -match '--app|--gui|electron') { throw 'Launcher content wrong' }
  foreach ($f in @('wezterm-gnosis.lua','Start-Gnosis.ps1','Start-Gnosis.vbs')) {
    if (-not (Test-Path -LiteralPath (Join-Path $script:StateDir $f))) { throw ('Missing ' + $f) }
  }
  $tk = $null; $te = $null
  [System.Management.Automation.Language.Parser]::ParseInput($ps1,[ref]$tk,[ref]$te) | Out-Null
  if ($te.Count -gt 0) { throw 'Generated launcher does not parse' }
  Write-Host 'OK: Unicode/space path launcher + shortcut chain ends in gnosis --tui'
} finally {
  $env:LOCALAPPDATA = $oldLocal
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# 4. PowerShell -> Bash transport (CRLF, quotes, spaces) with real Git Bash.
$bash = @((Join-Path $env:ProgramFiles 'Git\bin\bash.exe'),(Join-Path $env:ProgramFiles 'Git\usr\bin\bash.exe')) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bash) { throw 'Git Bash is required for the WSL transport test' }
$crlf = ([string][char]13 + [string][char]10)
$sample = @('set -eu','value="hello world"','if test "$value" = "hello world"; then','  printf "WSL_TRANSPORT_OK:%s\n" "$value"','fi') -join $crlf
$line = ConvertTo-WslBashCommand $sample
if ($line.Contains([string][char]10) -or $line.Contains([string][char]13)) { throw 'Encoded command contains a newline' }
$output = & $bash -c $line
if ($LASTEXITCODE -ne 0 -or (($output -join '') -ne 'WSL_TRANSPORT_OK:hello world')) { throw ('Transport broke CRLF/quotes: ' + ($output -join ' ')) }
# a failing script must surface its exit code, not be swallowed
& $bash -c (ConvertTo-WslBashCommand 'exit 7') | Out-Null
if ($LASTEXITCODE -ne 7) { throw ('Exit code not propagated: ' + $LASTEXITCODE) }
Write-Host 'OK: transport preserves CRLF/quoting and propagates exit codes'

# 5. Real generated Linux scripts: syntax check under Bash.
foreach ($pair in @(@('bootstrap',(Get-LinuxBootstrapScript '')),@('bootstrap-ref',(Get-LinuxBootstrapScript 'v1.0')),@('verify',(Get-LinuxVerifyScript)))) {
  $c = (ConvertTo-WslBashCommand $pair[1]).Replace('bash "$f"; rc=$?','bash -n "$f"; rc=$?')
  & $bash -c $c
  if ($LASTEXITCODE -ne 0) { throw ('Bash syntax failure: ' + $pair[0]) }
}
$threw = $false
try { Get-LinuxBootstrapScript 'x; rm -rf ~' | Out-Null } catch { $threw = $true }
if (-not $threw) { throw 'Unsafe -Ref was accepted' }
Write-Host 'OK: generated Linux scripts parse; unsafe ref rejected'

# 6. Vim feature check used by the verify script, run against real Git Bash with a fake vim.
$vimCheck = (Get-LinuxVerifyScript)
foreach ($need in @('+$f','popupwin','textprop','channel','timers','job')) { if (-not $vimCheck.Contains($need)) { throw ('verify does not check ' + $need) } }
Write-Host 'OK: verify script checks every required Vim feature on the full output'

# 7. Default entry selects the terminal installer; Electron stays opt-in.
$entry = Join-Path $root 'install\install.ps1'
$t2 = Join-Path $env:TEMP ('gnosis-entry-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $t2 -Force | Out-Null
try {
  Copy-Item -LiteralPath $entry -Destination (Join-Path $t2 'install.ps1')
  '[CmdletBinding()]param([switch]$SkipInstall,[switch]$NoShortcut,[switch]$Resume,[switch]$Yes,[string]$Ref,[string]$Distro)' + "`n" + '[IO.File]::WriteAllText((Join-Path $PSScriptRoot "terminal-invoked"), "yes")' | Set-Content -LiteralPath (Join-Path $t2 'install-windows.ps1') -Encoding Ascii
  'param([switch]$NoSystem,[switch]$NoShortcut)' + "`n" + '[IO.File]::WriteAllText((Join-Path $PSScriptRoot "native-invoked"), "yes")' | Set-Content -LiteralPath (Join-Path $t2 'install-native.ps1') -Encoding Ascii
  & (Join-Path $t2 'install.ps1') -NoSystem -NoShortcut
  if (-not (Test-Path (Join-Path $t2 'terminal-invoked'))) { throw 'Default installer did not select terminal Gnosis' }
  if (Test-Path (Join-Path $t2 'native-invoked')) { throw 'Electron ran by default' }
  & (Join-Path $t2 'install.ps1') -NativeApp -NoSystem -NoShortcut
  if (-not (Test-Path (Join-Path $t2 'native-invoked'))) { throw 'Electron not reachable via -NativeApp' }
  Write-Host 'OK: default=terminal; Electron is opt-in'
} finally { Remove-Item -LiteralPath $t2 -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host 'ALL WINDOWS INSTALLER TESTS PASSED'
