#Requires -Version 5.1
# Gnosis for Windows: WSL2 + Ubuntu + WezTerm + terminal (Vim) Gnosis.
# ASCII-only on purpose: Windows PowerShell 5.1 misreads UTF-8 files without BOM.
#
# The desktop/Start-menu icon ALWAYS ends in:  ~/.local/bin/gnosis --tui
# (ordinary Vim in WezTerm). It never starts the Electron app, gVim or a browser.
#
# Phases are recorded in %LOCALAPPDATA%\Gnosis\install-state.json so a run that
# needs a Windows restart or an Ubuntu first-run can continue where it stopped.
[CmdletBinding()]
param(
  [switch]$SkipInstall,   # never install anything; report what is missing and stop
  [switch]$NoShortcut,
  [switch]$Resume,        # started by the post-reboot RunOnce entry
  [switch]$Yes,           # do not ask before installing WSL / WezTerm (reboot is still asked)
  [string]$Ref = '',      # optional Git tag/branch for the Linux-side checkout
  [string]$Distro = '',   # optional explicit WSL distribution name
  [string]$ShortcutDir = '' # tests only: write one Gnosis.lnk here instead of Desktop/Start menu
)
$ErrorActionPreference = 'Stop'
$script:RepoUrl  = 'https://github.com/Yurii7812/gnosis.git'
$script:StateDir = Join-Path $env:LOCALAPPDATA 'Gnosis'
$script:StateFile = Join-Path $script:StateDir 'install-state.json'
$script:LogFile  = Join-Path $script:StateDir 'install.log'
$script:RunOnceName = 'GnosisInstallResume'

# ---------------------------------------------------------------- logging
function Write-Log([string]$text) {
  try {
    New-Item -ItemType Directory -Force -Path $script:StateDir | Out-Null
    Add-Content -LiteralPath $script:LogFile -Value ((Get-Date -Format 's') + ' ' + $text) -Encoding UTF8
  } catch {}
}
function Say([string]$text) { Write-Host $text; Write-Log $text }
function Fail([string]$what, [string]$next) {
  Write-Log ('FAILED: ' + $what + ' | next: ' + $next)
  Write-Host ''
  Write-Host ('Gnosis install is NOT complete: ' + $what) -ForegroundColor Red
  Write-Host ('What to do: ' + $next) -ForegroundColor Yellow
  Write-Host ('Log file: ' + $script:LogFile)
  throw ('Gnosis install incomplete: ' + $what)
}
function Ask([string]$question) {
  if ($Yes) { return $true }
  return ((Read-Host ($question + ' [y/N]')) -match '^(y|yes)$')
}

# ---------------------------------------------------------------- state / resume
function Get-State {
  if (Test-Path -LiteralPath $script:StateFile) {
    try { return (Get-Content -LiteralPath $script:StateFile -Raw | ConvertFrom-Json) } catch {}
  }
  return $null
}
function Set-State([string]$phase, [string]$distro) {
  New-Item -ItemType Directory -Force -Path $script:StateDir | Out-Null
  $obj = @{ phase = $phase; distro = $distro; ref = $Ref; updated = (Get-Date -Format 's') }
  [IO.File]::WriteAllText($script:StateFile, ($obj | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
}
function Get-InstallerCopyDir {
  # Persist a copy of the installer so the post-reboot run does not need the network.
  $dir = Join-Path $script:StateDir 'installer'
  $src = Split-Path -Parent $PSCommandPath
  $srcRoot = Split-Path -Parent $src
  $target = Join-Path $dir 'install'
  New-Item -ItemType Directory -Force -Path $target | Out-Null
  $same = ((Resolve-Path -LiteralPath $src).Path -eq (Resolve-Path -LiteralPath $target).Path)
  if (-not $same) {
    Copy-Item -Path (Join-Path $src '*') -Destination $target -Recurse -Force
    $icons = Join-Path $srcRoot 'assets\icons'
    if (Test-Path -LiteralPath $icons) {
      $iconTarget = Join-Path $dir 'assets\icons'
      New-Item -ItemType Directory -Force -Path $iconTarget | Out-Null
      Copy-Item -Path (Join-Path $icons '*') -Destination $iconTarget -Recurse -Force
    }
  }
  return $target
}
function Register-Resume {
  $copy = Get-InstallerCopyDir
  $script1 = Join-Path $copy 'install-windows.ps1'
  $cmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $script1 + '" -Resume'
  if ($Ref) { $cmd += ' -Ref "' + $Ref + '"' }
  $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
  Set-ItemProperty -Path $key -Name $script:RunOnceName -Value $cmd
  Write-Log ('Registered RunOnce: ' + $cmd)
}
function Clear-Resume {
  Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name $script:RunOnceName -ErrorAction SilentlyContinue
}
function Request-Reboot([string]$reason) {
  Register-Resume
  Say ''
  Say ('A Windows restart is required: ' + $reason)
  Say 'After you sign in again, this installer continues automatically (one time).'
  if (Ask 'Restart Windows now?') {
    Restart-Computer -Force
  } else {
    Say 'Please restart Windows yourself. The installer will resume at your next sign-in.'
  }
  exit 0
}

# ---------------------------------------------------------------- Windows / WSL probes
function Test-IsAdmin {
  $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Test-WindowsSupported {
  $build = [Environment]::OSVersion.Version.Build
  if ($build -lt 19041) {
    Fail ('Windows build ' + $build + ' cannot run WSL2.') 'Use Windows 10 version 2004 (build 19041) or later, or Windows 11.'
  }
}
function Get-WslDistros {
  $ErrorActionPreference = 'Continue'  # native stderr must not become a terminating error in PS 5.1
  # wsl.exe prints UTF-16; strip NULs so Japanese/English Windows both work.
  $env:WSL_UTF8 = '1'
  $out = @(& wsl.exe --list --quiet 2>$null)
  if ($LASTEXITCODE -ne 0) { return @() }
  $names = @()
  foreach ($line in $out) {
    $n = (([string]$line) -replace [char]0, '').Trim()
    if ($n) { $names += $n }
  }
  return $names
}
function Select-UbuntuDistro([string[]]$names) {
  if ($Distro) { if ($names -contains $Distro) { return $Distro } else { return $null } }
  if ($names -contains 'Ubuntu') { return 'Ubuntu' }
  foreach ($n in $names) { if ($n -match '^Ubuntu(-[0-9]+\.[0-9]+)?$') { return $n } }
  return $null
}
function Test-WslUsable {
  $ErrorActionPreference = 'Continue'  # native stderr must not become a terminating error in PS 5.1
  # True only when wsl.exe really runs a Linux command (not merely exists).
  if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return $false }
  & wsl.exe --status *> $null
  return ($LASTEXITCODE -eq 0)
}
function Get-WslDistroUser([string]$name) {
  $ErrorActionPreference = 'Continue'  # native stderr must not become a terminating error in PS 5.1
  $u = & wsl.exe -d $name --exec id -un 2>$null
  if ($LASTEXITCODE -ne 0) { return $null }
  return (([string]($u | Select-Object -First 1)).Trim())
}
function Get-WslVersion([string]$name) {
  $ErrorActionPreference = 'Continue'  # native stderr must not become a terminating error in PS 5.1
  # `wsl -l -v` rows: "* Ubuntu  Running  2"
  $env:WSL_UTF8 = '1'
  foreach ($line in @(& wsl.exe --list --verbose 2>$null)) {
    $l = (([string]$line) -replace [char]0, '').Trim() -replace '^\*\s*', ''
    if ($l -match ('^' + [regex]::Escape($name) + '\s+\S+\s+([12])\s*$')) { return [int]$Matches[1] }
  }
  return 0
}

# ---------------------------------------------------------------- phase: WSL2 + Ubuntu
function Install-WslAndUbuntu {
  $ErrorActionPreference = 'Continue'  # native stderr must not become a terminating error in PS 5.1
  if ($SkipInstall) { Fail 'WSL2/Ubuntu is missing.' 'Run the installer again without -SkipInstall.' }
  $build = [Environment]::OSVersion.Version.Build
  try {
    $cs = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    if (-not $cs.HypervisorPresent -and $cpu -and -not $cpu.VirtualizationFirmwareEnabled) {
      Say 'WARNING: CPU virtualization looks disabled. WSL2 needs it; enable Intel VT-x / AMD-V (SVM) in the BIOS/UEFI if the next step fails.'
    }
  } catch {}
  Say 'WSL2 and Ubuntu are not ready. Installing them needs administrator approval (a Windows prompt will appear).'
  if (-not (Ask 'Install WSL2 and Ubuntu now?')) {
    Fail 'You declined WSL2/Ubuntu installation.' 'Run the installer again and answer y, or install Ubuntu for WSL2 yourself.'
  }
  Set-State 'wsl-install' ''
  if (-not (Test-WslUsable)) {
    Say 'Enabling WSL (admin prompt)...'
    $p = $null
    try {
      $p = Start-Process -FilePath 'wsl.exe' -ArgumentList '--install','--no-distribution' -Verb RunAs -Wait -PassThru
    } catch {
      Fail 'Administrator approval was not given (or is blocked by policy).' 'Approve the Windows prompt, or ask an administrator to run: wsl --install --no-distribution'
    }
    Write-Log ('wsl --install --no-distribution exit ' + $p.ExitCode)
    if ($p.ExitCode -eq 3010 -or -not (Test-WslUsable)) {
      Request-Reboot 'the WSL2 Windows features were just enabled.'
    }
    if ($p.ExitCode -ne 0) {
      Fail ('wsl --install failed with exit code ' + $p.ExitCode + '.') 'Check that virtualization is enabled in BIOS/UEFI and that Windows policy allows WSL, then run the installer again.'
    }
  }
  Say 'Installing Ubuntu (download; this can take several minutes)...'
  & wsl.exe --install -d Ubuntu --no-launch
  if ($LASTEXITCODE -ne 0) {
    Fail ('Ubuntu download/install failed (exit ' + $LASTEXITCODE + ').') 'Check your internet connection and run the installer again; it resumes from here.'
  }
}
function Complete-UbuntuFirstRun([string]$name) {
  $ErrorActionPreference = 'Continue'  # native stderr must not become a terminating error in PS 5.1
  $user = Get-WslDistroUser $name
  if ($user -and $user -ne 'root') { return $user }
  Say ''
  Say ('Ubuntu (' + $name + ') needs its first-time setup: choose a Linux username and password.')
  Say 'These are typed into Ubuntu itself; the Gnosis installer never sees or stores them.'
  $launcher = Get-Command ($name.ToLower() + '.exe') -ErrorAction SilentlyContinue
  if ($launcher) {
    & $launcher.Source install --ui=tui
  } else {
    Say 'When the Ubuntu prompt appears and the user is created, type "exit" to return here.'
    & wsl.exe -d $name
  }
  $user = Get-WslDistroUser $name
  if (-not $user -or $user -eq 'root') {
    Set-State 'ubuntu-first-run' $name
    Fail 'Ubuntu has no normal (non-root) user yet.' ('Open "' + $name + '" from the Start menu, create the user, then run the Gnosis installer again.')
  }
  return $user
}

# ---------------------------------------------------------------- WezTerm
function Find-WezTerm {
  # Prefers wezterm-gui.exe (no console window). Checks PATH, registry, usual
  # folders and the folders winget uses, so a missing PATH entry is harmless.
  $cands = New-Object System.Collections.ArrayList
  foreach ($n in @('wezterm-gui.exe','wezterm.exe')) {
    $c = Get-Command $n -ErrorAction SilentlyContinue
    if ($c) { [void]$cands.Add($c.Source) }
  }
  foreach ($hive in @('HKLM:','HKCU:')) {
    foreach ($n in @('wezterm-gui.exe','wezterm.exe')) {
      $k = $hive + '\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\' + $n
      try { $v = (Get-ItemProperty -LiteralPath $k -ErrorAction Stop).'(default)'; if ($v) { [void]$cands.Add($v) } } catch {}
    }
  }
  foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs'))) {
    if ($base) { foreach ($n in @('wezterm-gui.exe','wezterm.exe')) { [void]$cands.Add((Join-Path $base ('WezTerm\' + $n))) } }
  }
  $pkgs = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
  if (Test-Path -LiteralPath $pkgs) {
    foreach ($d in @(Get-ChildItem -LiteralPath $pkgs -Directory -Filter 'wez.wezterm*' -ErrorAction SilentlyContinue)) {
      foreach ($f in @(Get-ChildItem -LiteralPath $d.FullName -Recurse -Include 'wezterm-gui.exe','wezterm.exe' -ErrorAction SilentlyContinue)) { [void]$cands.Add($f.FullName) }
    }
  }
  foreach ($c in $cands) {
    if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) {
      # Prefer the GUI binary when only wezterm.exe was found.
      $gui = Join-Path (Split-Path -Parent $c) 'wezterm-gui.exe'
      if (Test-Path -LiteralPath $gui) { return $gui }
      return $c
    }
  }
  return $null
}
function Install-WezTerm {
  $ErrorActionPreference = 'Continue'  # native stderr must not become a terminating error in PS 5.1
  $exe = Find-WezTerm
  if ($exe) { Say ('WezTerm found: ' + $exe); return $exe }
  if ($SkipInstall) { Fail 'WezTerm is missing.' 'Run the installer again without -SkipInstall.' }
  if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    Fail 'WezTerm is missing and winget (App Installer) is not available.' 'Install "App Installer" from the Microsoft Store (or WezTerm from https://wezterm.org/install/windows.html), then run the installer again.'
  }
  if (-not (Ask 'Install WezTerm with winget?')) { Fail 'You declined WezTerm installation.' 'Run the installer again and answer y.' }
  Say 'Installing WezTerm...'
  & winget.exe install --exact --id wez.wezterm --accept-package-agreements --accept-source-agreements --silent
  Write-Log ('winget wezterm exit ' + $LASTEXITCODE)
  $exe = Find-WezTerm
  if (-not $exe) {
    Fail 'WezTerm was installed but its executable could not be located.' 'Sign out and in (or open a new PowerShell) and run the installer again; it resumes here.'
  }
  return $exe
}

# ---------------------------------------------------------------- PowerShell -> WSL transport
# PowerShell 5.1 corrupts multi-line arguments passed to wsl.exe. The script is sent as ONE
# ASCII base64 word, decoded to a temp file inside Ubuntu and run with bash. stdin stays
# attached, so sudo can still ask for the Ubuntu password.
function ConvertTo-WslBashCommand([string]$source) {
  $cr = [string][char]13
  $lf = [string][char]10
  $normalized = $source.Replace(($cr + $lf),$lf).Replace($cr,$lf)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized + $lf)
  $encoded = [Convert]::ToBase64String($bytes)
  return ('f=$(mktemp) && printf %s ' + $encoded + ' | base64 -d > "$f"; bash "$f"; rc=$?; rm -f "$f"; exit $rc')
}
function Invoke-WslBash([string]$name,[string]$source,[string]$operation) {
  $ErrorActionPreference = 'Continue'  # native stderr must not become a terminating error in PS 5.1
  $command = ConvertTo-WslBashCommand $source
  if ($command.Length -gt 24000) { Fail ($operation + ': internal script too long for the Windows command line.') 'Report this bug.' }
  Write-Log ('WSL run: ' + $operation)
  & wsl.exe -d $name --exec bash -c $command
  if ($LASTEXITCODE -ne 0) {
    Fail ($operation + ' failed inside Ubuntu (exit code ' + $LASTEXITCODE + ').') 'Read the messages above (network or sudo problems are most common), then run the installer again; finished steps are skipped.'
  }
}
function Get-LinuxBootstrapScript([string]$ref) {
  if ($ref -and $ref -notmatch '^[A-Za-z0-9._/-]+$') { Fail 'Invalid -Ref value.' 'Use a plain branch or tag name.' }
  $branchArg = ''; $installArg = ''
  if ($ref) { $branchArg = '--branch ' + $ref; $installArg = ' --no-update' }
  $t = @'
set -eu
trap 'rc=$?; echo "[gnosis-installer] failed near line $LINENO (exit $rc)" >&2' EXIT
if [ "$(id -u)" = 0 ]; then echo "Refusing to install as root. Create a normal Ubuntu user first." >&2; trap - EXIT; exit 20; fi
need=""
command -v git >/dev/null 2>&1 || need="$need git"
command -v curl >/dev/null 2>&1 || need="$need curl"
[ -e /etc/ssl/certs/ca-certificates.crt ] || need="$need ca-certificates"
if [ -n "$need" ]; then
  echo "Installing:$need (sudo may ask for your Ubuntu password)"
  sudo apt-get update
  sudo apt-get install -y $need
fi
if [ -d "$HOME/gnosis/.git" ]; then
  echo "Existing Gnosis checkout found; keeping it (install.sh updates it safely)."
elif [ -e "$HOME/gnosis" ]; then
  echo "$HOME/gnosis exists but is not a Gnosis Git checkout; not touching it." >&2; trap - EXIT; exit 21
else
  git clone __BRANCH__ __REPO__ "$HOME/gnosis"
fi
cd "$HOME/gnosis"
trap - EXIT
exec sh install/install.sh --yes__NOUPDATE__
'@
  return $t.Replace('__BRANCH__',$branchArg).Replace('__REPO__',$script:RepoUrl).Replace('__NOUPDATE__',$installArg)
}
function Get-LinuxVerifyScript {
  return @'
set -eu
fail() { echo "VERIFY FAILED: $1" >&2; exit 30; }
test -x "$HOME/.local/bin/gnosis" || fail "launcher ~/.local/bin/gnosis missing"
test -x "$HOME/gnosis/bin/gnosis" || fail "bin/gnosis missing in ~/gnosis"
H="${XDG_DATA_HOME:-$HOME/.local/share}/gnosis"
test -f "$H/vimrc" || fail "Gnosis-only vimrc missing ($H/vimrc)"
for p in fzf fzf.vim vim-surround; do test -d "$H/plugins/$p" || fail "plugin $p missing"; done
command -v python3 >/dev/null 2>&1 || fail "python3 missing"
command -v git >/dev/null 2>&1 || fail "git missing"
out=$(vim --version 2>/dev/null) || fail "vim does not run"
for f in job channel timers textprop popupwin; do
  printf '%s' "$out" | grep -q "+$f" || fail "Vim lacks +$f"
done
ver=$(printf '%s' "$out" | sed -n 's/.*Vi IMproved \([0-9]*\)\.\([0-9]*\).*/\1 \2/p' | head -1)
set -- $ver
{ [ "${1:-0}" -gt 8 ] || { [ "${1:-0}" -eq 8 ] && [ "${2:-0}" -ge 2 ]; }; } || fail "Vim older than 8.2"
grep -q -- '--tui' "$HOME/gnosis/bin/gnosis" || fail "launcher has no --tui mode"
"$HOME/.local/bin/gnosis" --doctor >/dev/null 2>&1 || fail "gnosis --doctor reported problems (run: wsl -d Ubuntu -- ~/.local/bin/gnosis --doctor)"
echo "VERIFY OK"
'@
}

# ---------------------------------------------------------------- Windows launcher
function Get-LauncherPs1([string]$name) {
  if (-not $name) { Fail 'Internal error: empty WSL distribution name for the launcher.' 'Report this bug.' }
  $t = @'
# Gnosis launcher (generated). Opens ordinary Vim Gnosis in WezTerm via WSL: gnosis --tui
$ErrorActionPreference = 'Stop'
$distro = '__DISTRO__'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
function Show-Problem([string]$m) {
  try { Add-Content -LiteralPath (Join-Path $dir 'launch.log') -Value ((Get-Date -Format 's') + ' ' + $m) } catch {}
  try { Add-Type -AssemblyName System.Windows.Forms; [void][Windows.Forms.MessageBox]::Show($m + "`r`nLog: " + (Join-Path $dir 'launch.log'), 'Gnosis') } catch {}
}
try {
  $size = 16
  try {
    $raw = & wsl.exe -d $distro --exec bash -c 'cat "${XDG_DATA_HOME:-$HOME/.local/share}/gnosis/terminal.json"' 2>$null
    if ($LASTEXITCODE -eq 0) {
      $data = ($raw -join "`n") | ConvertFrom-Json
      if ($data.fontSize -ge 6 -and $data.fontSize -le 48) { $size = [int]$data.fontSize }
    }
  } catch {}
  $exe = $null
  foreach ($n in @('wezterm-gui.exe','wezterm.exe')) {
    $c = Get-Command $n -ErrorAction SilentlyContinue
    if ($c) { $exe = $c.Source; break }
  }
  if (-not $exe) {
    $pkgs = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    $list = @("$env:ProgramFiles\WezTerm\wezterm-gui.exe", "$env:LOCALAPPDATA\Programs\WezTerm\wezterm-gui.exe")
    if (Test-Path -LiteralPath $pkgs) {
      $list += @(Get-ChildItem -LiteralPath $pkgs -Recurse -Filter 'wezterm-gui.exe' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    }
    $exe = $list | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
  }
  if (-not $exe) { throw 'WezTerm was not found. Re-run the Gnosis installer.' }
  # Gnosis-only WezTerm config: the user's own wezterm.lua is neither read nor changed.
  $conf = Join-Path $dir 'wezterm-gnosis.lua'
  $q = [char]34
  $args1 = '--config-file ' + $q + $conf + $q + ' --config font_size=' + $size + ' start -- wsl.exe -d ' + $distro + ' --cd ~ --exec bash -c ' + $q + 'exec $HOME/.local/bin/gnosis --tui' + $q
  Start-Process -FilePath $exe -ArgumentList $args1
} catch {
  Show-Problem ('Gnosis could not start: ' + $_.Exception.Message)
  exit 1
}
'@
  return $t.Replace('__DISTRO__',$name)
}
function Get-LauncherVbs {
  # Runs the PowerShell launcher with no console window at all (no flash).
  # The path is derived at run time, so Unicode user names never enter this file.
  return @'
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
q = Chr(34)
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & q & dir & "\Start-Gnosis.ps1" & q, 0, False
'@
}
function Get-WezTermLua {
  return @'
-- Gnosis-only WezTerm settings (generated). The user's own wezterm.lua is not used here.
local wezterm = require 'wezterm'
local config = wezterm.config_builder and wezterm.config_builder() or {}
config.enable_tab_bar = false
config.window_close_confirmation = 'NeverPrompt'
config.exit_behavior = 'Close'
config.window_padding = { left = 8, right = 8, top = 8, bottom = 8 }
config.color_scheme = 'Builtin Dark'
return config
'@
}
function Install-Launcher([string]$name,[string]$user) {
  $dest = $script:StateDir
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  $enc = New-Object Text.UTF8Encoding($false)
  [IO.File]::WriteAllText((Join-Path $dest 'Start-Gnosis.ps1'), (Get-LauncherPs1 $name), (New-Object Text.UTF8Encoding($true)))
  [IO.File]::WriteAllText((Join-Path $dest 'Start-Gnosis.vbs'), (Get-LauncherVbs), [Text.Encoding]::ASCII)
  [IO.File]::WriteAllText((Join-Path $dest 'wezterm-gnosis.lua'), (Get-WezTermLua), $enc)
  # icon: prefer the bundled .ico, else the copy built inside Ubuntu
  $icon = Join-Path $dest 'gnosis.ico'
  $src = $null
  $base = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
  foreach ($c in @((Join-Path $base 'assets\icons\gnosis.ico'))) { if (Test-Path -LiteralPath $c) { $src = $c; break } }
  if (-not $src) {
    $unc = '\\wsl.localhost\' + $name + '\home\' + $user + '\gnosis\assets\icons\gnosis.ico'
    if (Test-Path -LiteralPath $unc) { $src = $unc }
  }
  if ($src) { Copy-Item -LiteralPath $src -Destination $icon -Force }
  if ($NoShortcut) { Say 'Shortcuts skipped (-NoShortcut).'; return }
  $shell = New-Object -ComObject WScript.Shell
  $vbs = Join-Path $dest 'Start-Gnosis.vbs'
  $links = @(
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Gnosis.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'Gnosis.lnk')
  )
  if ($ShortcutDir) { $links = @((Join-Path $ShortcutDir 'Gnosis.lnk')) }
  foreach ($path in $links) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    $l = $shell.CreateShortcut($path)
    $l.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $l.Arguments = '//B //Nologo "' + $vbs + '"'
    $l.WorkingDirectory = $dest
    $l.Description = 'Gnosis (Vim in WezTerm on WSL2 Ubuntu)'
    if (Test-Path -LiteralPath $icon) { $l.IconLocation = $icon }
    $l.Save()
    $chk = $shell.CreateShortcut($path)
    if ($chk.Arguments -notlike '*Start-Gnosis.vbs*') { Fail ('Shortcut was not written correctly: ' + $path) 'Run the installer again.' }
    Say ('Shortcut: ' + $path)
  }
  # The launcher chain must end in `gnosis --tui` and nothing else.
  $ps1 = [IO.File]::ReadAllText((Join-Path $dest 'Start-Gnosis.ps1'))
  if ($ps1 -notmatch 'gnosis --tui' -or $ps1 -match 'gnosis --(app|gui)') {
    Fail 'Launcher does not end in gnosis --tui.' 'Report this bug.'
  }
}

# ---------------------------------------------------------------- main
function Invoke-GnosisWindowsInstall {
  Write-Log '--- install start ---'
  Say 'Gnosis for Windows: WSL2 Ubuntu + WezTerm + Vim (terminal version)'
  $mutex = New-Object Threading.Mutex($false, 'Local\GnosisWindowsInstaller')
  if (-not $mutex.WaitOne(0)) { Fail 'Another Gnosis installer is already running.' 'Wait for it to finish.' }
  try {
    Test-WindowsSupported
    $prior = Get-State
    if ($Resume -and $prior) { Say ('Resuming after: ' + $prior.phase); if (-not $Ref -and $prior.ref) { $script:Ref = $prior.ref } }
    Clear-Resume

    $names = if (Test-WslUsable) { Get-WslDistros } else { @() }
    $name = Select-UbuntuDistro $names
    if (-not $name) {
      Install-WslAndUbuntu
      $name = Select-UbuntuDistro (Get-WslDistros)
      if (-not $name) { Fail 'Ubuntu is still not registered with WSL.' 'Restart Windows and run the installer again.' }
    }
    if ((Get-WslVersion $name) -eq 1) {
      Fail ($name + ' runs as WSL 1.') ('Run in PowerShell: wsl --set-version ' + $name + ' 2   (it keeps your files), then run the installer again.')
    }
    Set-State 'ubuntu-ready' $name
    $user = Complete-UbuntuFirstRun $name
    Say ('Using WSL distribution "' + $name + '", Linux user "' + $user + '".')

    $wez = Install-WezTerm
    Set-State 'linux-setup' $name
    Say 'Installing/updating Gnosis inside Ubuntu (sudo may ask for your Ubuntu password)...'
    Invoke-WslBash $name (Get-LinuxBootstrapScript $Ref) 'Linux-side Gnosis setup'
    Invoke-WslBash $name (Get-LinuxVerifyScript) 'Gnosis verification'

    Set-State 'launcher' $name
    Install-Launcher $name $user
    Set-State 'done' $name
    Say ''
    Say 'Gnosis is installed and verified.'
    if (-not $NoShortcut) { Say 'Double-click "Gnosis" on the Desktop or in the Start menu.' }
    Write-Log '--- install ok ---'
  } finally {
    $mutex.ReleaseMutex(); $mutex.Dispose()
  }
}

# Dot-sourcing (tests) loads the functions only.
if ($MyInvocation.InvocationName -eq '.') { return }
try { Invoke-GnosisWindowsInstall } catch {
  Write-Log ('ERROR: ' + $_.Exception.Message)
  if ($_.Exception.Message -notlike 'Gnosis install incomplete*') {
    Write-Host ('Gnosis install stopped: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host ('Log file: ' + $script:LogFile)
  }
  exit 1
}
