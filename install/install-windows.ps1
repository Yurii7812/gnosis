#Requires -Version 5.1
# Windows bootstrap: WSL2 Ubuntu + WezTerm + Gnosis; sensitive operations require consent.
[CmdletBinding()]
param([switch]$SkipInstall, [switch]$NoShortcut)
$ErrorActionPreference = 'Stop'
function Ask([string]$question) { return (Read-Host "$question [y/N]") -match '^(y|yes)$' }
Write-Host 'Gnosis Windows: Ubuntu on WSL2 and WezTerm'
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
  throw 'Windows 10 2004+ or Windows 11 and WSL support are required.'
}
$list = @(& wsl.exe --list --quiet 2>$null)
$ubuntuName = $null
foreach ($entry in $list) {
  $candidate = ([string]$entry -replace [char]0, '').Trim()
  if ($candidate -eq 'Ubuntu') { $ubuntuName = $candidate; break }
  if (-not $ubuntuName -and $candidate -match '^Ubuntu(-[0-9]+\.[0-9]+)?$') {
    $ubuntuName = $candidate
  }
}
if (-not $ubuntuName) {
  Write-Host 'WSL2/Ubuntu installation may require admin privileges and a reboot.'
  if ($SkipInstall -or -not (Ask 'Install WSL2 and Ubuntu?')) { exit 1 }
  & wsl.exe --install -d Ubuntu
  if ($LASTEXITCODE -ne 0) { throw 'WSL install failed. Run PowerShell as Administrator.' }
  Write-Host 'Complete Ubuntu first-run setup and reboot if prompted, then rerun.'
  exit 0
}
$wez = Get-Command wezterm.exe -ErrorAction SilentlyContinue
if (-not $wez) {
  foreach ($path in @("$env:LOCALAPPDATA\Programs\WezTerm\wezterm.exe",
                     "$env:ProgramFiles\WezTerm\wezterm.exe")) {
    if (Test-Path $path) { $wez = Get-Item $path; break }
  }
}
if (-not $wez) {
  if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw 'winget/App Installer is required to install WezTerm.' }
  if ($SkipInstall -or -not (Ask 'Install WezTerm using winget?')) { exit 1 }
  & winget install --exact --id wez.wezterm --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) { throw 'WezTerm installation failed' }
}
# Validate WezTerm before modifying the Ubuntu installation.
# Package managers may finish without updating PATH in the current shell.
$wezExe = Get-Command wezterm.exe -ErrorAction SilentlyContinue
if (-not $wezExe) {
  foreach ($p in @(
    "$env:LOCALAPPDATA\Programs\WezTerm\wezterm.exe",
    "$env:ProgramFiles\WezTerm\wezterm.exe"
  )) {
    if (Test-Path -LiteralPath $p) { $wezExe = $p; break }
  }
}
if (-not $wezExe) {
  throw 'WezTerm executable could not be found after installation. Open a new PowerShell and retry; setup is incomplete.'
}
Write-Host 'Installing terminal-based Gnosis in Ubuntu (sudo may request password).'
$bootstrap = @'
set -eu
if ! command -v git >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y git
fi
if [ ! -d "$HOME/gnosis/.git" ]; then
  git clone https://github.com/Yurii7812/gnosis.git "$HOME/gnosis"
fi
cd "$HOME/gnosis"
sh install/install.sh --yes
'@
& wsl.exe -d $ubuntuName --exec bash -lc $bootstrap
if ($LASTEXITCODE -ne 0) { throw 'Linux-side Gnosis setup failed' }

# Completion means the terminal version is actually installed, not merely
# that WSL and Git were downloaded. Do not make a broken desktop shortcut.
$verify = @'
set -eu
test -x "$HOME/.local/bin/gnosis"
test -f "$HOME/.local/share/gnosis/vimrc"
test -d "$HOME/.local/share/gnosis/plugins/fzf"
command -v vim >/dev/null
command -v python3 >/dev/null
'@
& wsl.exe -d $ubuntuName --exec bash -lc $verify
if ($LASTEXITCODE -ne 0) {
  throw 'Gnosis dependencies are incomplete in Ubuntu. Shortcut creation was cancelled.'
}

$dest = Join-Path $env:LOCALAPPDATA 'Gnosis'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$start = Join-Path $dest 'Start-Gnosis.ps1'
$startContent = @'
$ErrorActionPreference = 'Stop'
$distro = '__GNOSIS_DISTRO__'
$size = 16
try {
  $raw = & wsl.exe -d $distro --exec bash -lc 'cat "$HOME/.local/share/gnosis/terminal.json"'
  if ($LASTEXITCODE -eq 0) {
    $data = ($raw -join [Environment]::NewLine) | ConvertFrom-Json
    if ($data.fontSize -ge 6 -and $data.fontSize -le 48) { $size = [int]$data.fontSize }
  }
} catch {}
$found = Get-Command wezterm.exe -ErrorAction SilentlyContinue
if ($found) { $exe = $found.Source } else {
  $exe = @("$env:LOCALAPPDATA\Programs\WezTerm\wezterm.exe",
           "$env:ProgramFiles\WezTerm\wezterm.exe") |
         Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $exe) { throw 'WezTerm executable missing' }
& $exe --config "font_size=$size" --config "enable_tab_bar=false" start -- wsl.exe -d $distro --exec bash -lc 'exec "$HOME/.local/bin/gnosis" --tui'
'@
$startContent = $startContent.Replace('__GNOSIS_DISTRO__', $ubuntuName)
$startContent | Set-Content -LiteralPath $start -Encoding Ascii
# Confirm the startup script was written before making a shortcut.
if (-not (Test-Path -LiteralPath $start)) { throw 'Gnosis startup script was not created.' }
if (-not $NoShortcut) {
  $shell = New-Object -ComObject WScript.Shell
  $iconPath = Join-Path $PSScriptRoot '..\assets\icons\gnosis.ico'
  try {
    $wslUser = ((& wsl.exe -d $ubuntuName --exec id -un | Select-Object -First 1) -as [string]).Trim()
    $unc = '\\wsl.localhost\' + $ubuntuName + '\home\' + $wslUser + '\.local\share\gnosis\generated-icons\icons\gnosis.ico'
    if (Test-Path $unc) { $iconPath = $unc }
  } catch { Write-Host 'Using the bundled Gnosis icon instead.' }
  $localIcon = Join-Path $dest 'gnosis.ico'
  if (Test-Path $iconPath) {
    Copy-Item -LiteralPath $iconPath -Destination $localIcon -Force
  }
  $links = @(
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Gnosis.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'Gnosis.lnk')
  )
  foreach ($shortcut in $links) {
    New-Item -ItemType Directory -Force -Path (Split-Path $shortcut -Parent) | Out-Null
    $link = $shell.CreateShortcut($shortcut)
    $link.TargetPath = (Join-Path $PSHOME 'powershell.exe')
    $link.Arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $start + '"'
    $link.WorkingDirectory = $dest
    $link.Description = 'Gnosis (Vim in WezTerm / Ubuntu WSL)'
    if (Test-Path $localIcon) { $link.IconLocation = $localIcon }
    $link.Save()
    if (-not (Test-Path -LiteralPath $shortcut)) {
      throw ('Could not create Gnosis shortcut: ' + $shortcut)
    }
    Write-Host ('Gnosis shortcut: ' + $shortcut)
  }
}
Write-Host "Gnosis terminal launcher ready: $start"
if (-not $NoShortcut) {
  Write-Host 'Gnosis is available from the Desktop and Start Menu.'
} else {
  Write-Host 'Gnosis shortcuts were skipped by request (-NoShortcut).'
}
