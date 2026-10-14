#Requires -Version 5.1
# Native Windows Electron GUI installer. ASCII-only for Windows PowerShell 5.1.
[CmdletBinding()]
param([switch]$NoSystem,[switch]$NoShortcut)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$homeDir = if ($env:GNOSIS_HOME) { $env:GNOSIS_HOME } else { Join-Path $env:APPDATA 'Gnosis' }
$web = Join-Path $repo 'web'
function Which([string]$name) {
  $c = Get-Command $name -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  return $null
}
function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
              [Environment]::GetEnvironmentVariable('Path','User')
}
function Find-Vim {
  if (Which 'vim.exe') { return (Which 'vim.exe') }
  foreach ($root in @($env:ProgramFiles,[Environment]::GetEnvironmentVariable('ProgramFiles(x86)'),$env:LOCALAPPDATA)) {
    if (-not $root) { continue }
    $dir = Join-Path $root 'Vim'
    if (-not (Test-Path $dir)) { continue }
    $found = Get-ChildItem $dir -Filter vim.exe -Recurse -File -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if ($found) { return $found.FullName }
  }
  return $null
}
function Vim-Ok([string]$exe) {
  if (-not $exe -or -not (Test-Path $exe)) { return $false }
  $result = (& $exe --version 2>$null | Select-Object -First 50) -join ' '
  foreach ($f in @('job','channel','timers','textprop','popupwin')) {
    if ($result -notmatch ('\+' + $f + '\b')) { return $false }
  }
  return $true
}
function Need([string]$name,[string]$id,[bool]$missing) {
  if (-not $missing) { return }
  if ($NoSystem) { throw ('Missing required dependency: ' + $name) }
  if (-not (Which 'winget.exe')) { throw 'winget is required to install missing dependencies.' }
  Write-Host ('Installing ' + $name + ' using winget')
  & winget.exe install --id $id -e --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) { throw ('Installation failed: ' + $name) }
  Refresh-Path
}
function Run([string]$exe,[string[]]$args,[string]$label) {
  Write-Host ('Setting up: ' + $label)
  & $exe @args
  if ($LASTEXITCODE -ne 0) { throw ($label + ' failed with exit code ' + $LASTEXITCODE) }
}
function PSQuote([string]$text) { return "'" + $text.Replace("'","''") + "'" }

Write-Host 'Gnosis Windows GUI: Electron + native Vim (no WSL required).'
Need 'Git' 'Git.Git' (-not [bool](Which 'git.exe'))
Need 'Vim' 'vim.vim' (-not (Vim-Ok (Find-Vim)))
Need 'Python' 'Python.Python.3.12' (-not [bool](Which 'py.exe') -and -not [bool](Which 'python.exe'))
Need 'Node.js' 'OpenJS.NodeJS.LTS' (-not [bool](Which 'node.exe'))
Need 'npm' 'OpenJS.NodeJS.LTS' (-not [bool](Which 'npm.cmd'))
Need 'fzf' 'junegunn.fzf' (-not [bool](Which 'fzf.exe'))
Need 'ripgrep' 'BurntSushi.ripgrep.MSVC' (-not [bool](Which 'rg.exe'))
$vim = Find-Vim; $git = Which 'git.exe'; $npm = Which 'npm.cmd'
$py = if (Which 'py.exe') { Which 'py.exe' } else { Which 'python.exe' }
if (-not (Vim-Ok $vim) -or -not $git -or -not $npm -or -not $py) {
  throw 'A required dependency is not visible yet. Open a fresh PowerShell and retry.'
}

foreach ($folder in @('plugins','themes','logs','state')) {
  New-Item -ItemType Directory -Force -Path (Join-Path $homeDir $folder) | Out-Null
}
foreach ($p in @(@('fzf','junegunn/fzf'),@('fzf.vim','junegunn/fzf.vim'),@('vim-surround','tpope/vim-surround'))) {
  $dst = Join-Path (Join-Path $homeDir 'plugins') $p[0]
  if (Test-Path (Join-Path $dst '.git')) {
    Run $git @('-C',$dst,'pull','--ff-only') ('plugin ' + $p[0])
  } elseif (-not (Test-Path $dst)) {
    Run $git @('clone','--depth','1',('https://github.com/' + $p[1] + '.git'),$dst) ('plugin ' + $p[0])
  } else {
    throw ('Plugin directory not managed by Git: ' + $dst)
  }
}
# Dedicated Gnosis vimrc, never source Windows _vimrc.
$vsrc = (Join-Path $repo 'vimrc_gnosis').Replace('\','/').Replace("'","''")
$vimrc = "execute 'source ' . fnameescape('" + $vsrc + "')" + [Environment]::NewLine
[IO.File]::WriteAllText((Join-Path $homeDir 'vimrc'),$vimrc,(New-Object Text.UTF8Encoding $false))
$pyArgs = if ([IO.Path]::GetFileName($py).ToLowerInvariant() -eq 'py.exe') { @('-3') } else { @() }
Run $py ($pyArgs + @('-m','pip','install','--user','-r',(Join-Path $repo 'python\requirements.txt'),'pillow')) 'Python helpers'
Push-Location $web
try {
  Run $npm @('ci','--no-audit','--no-fund','--include=optional') 'Electron dependencies'
  Run $npm @('run','rebuild:pty') 'Windows native terminal backend'
  Run $npm @('run','build') 'Gnosis desktop interface'
} finally { Pop-Location }
$electron = Join-Path $web 'node_modules\electron\dist\electron.exe'
if (-not (Test-Path $electron)) { throw 'Electron executable is missing; desktop setup incomplete.' }
if (-not (Test-Path (Join-Path $web 'bundle.js'))) { throw 'Interface build is missing; desktop setup incomplete.' }
if (-not (Test-Path (Join-Path $web 'node_modules\node-pty'))) { throw 'Terminal backend is missing; desktop setup incomplete.' }

# Generate a Gnosis icon from the high-contrast assets.
$icon = Join-Path $repo 'assets\icons\gnosis.ico'
$env:GNOSIS_ICON_OUTPUT_ROOT = Join-Path $homeDir 'generated-icons'
try {
  Run $py ($pyArgs + @((Join-Path $repo 'tools\build_icons.py'))) 'High-contrast icon'
  $generated = Join-Path $env:GNOSIS_ICON_OUTPUT_ROOT 'icons\gnosis.ico'
  if (Test-Path $generated) { $icon = $generated }
} finally { Remove-Item Env:GNOSIS_ICON_OUTPUT_ROOT -ErrorAction SilentlyContinue }

# A dedicated launcher supplies Gnosis-specific paths without modifying PATH.
$launcher = Join-Path $homeDir 'Start-Gnosis.ps1'
$cmd = @(
  '$ErrorActionPreference = ' + (PSQuote 'Stop'),
  '$env:GNOSIS_HOME = ' + (PSQuote $homeDir),
  '$env:GNOSIS_VIMRC = ' + (PSQuote (Join-Path $homeDir 'vimrc')),
  '$env:GNOSIS_VIM = ' + (PSQuote $vim),
  '$exe = ' + (PSQuote $electron),
  '$app = ' + (PSQuote $web),
  'if (-not (Test-Path $exe)) { throw ' + (PSQuote 'Missing Gnosis desktop app') + ' }',
  'Start-Process -FilePath $exe -ArgumentList (' + (PSQuote '"') + ' + $app + ' + (PSQuote '"') + ') -WorkingDirectory $app'
) -join [Environment]::NewLine
[IO.File]::WriteAllText($launcher,$cmd,(New-Object Text.UTF8Encoding $false))
if (-not $NoShortcut) {
  $shell = New-Object -ComObject WScript.Shell
  foreach ($target in @(
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Gnosis.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'Gnosis.lnk'))) {
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    $link = $shell.CreateShortcut($target)
    $link.TargetPath = (Join-Path $PSHOME 'powershell.exe')
    $link.Arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $launcher + '"'
    $link.WorkingDirectory = $web
    if (Test-Path $icon) { $link.IconLocation = $icon }
    $link.Description = 'Gnosis desktop application'
    $link.Save()
    if (-not (Test-Path $target)) { throw ('Failed to create shortcut: ' + $target) }
    Write-Host ('Created: ' + $target)
  }
}
Write-Host 'Gnosis Windows desktop application installed.'
Write-Host ('App: ' + $electron)
Write-Host 'Open the Gnosis desktop icon to start the GUI.'
