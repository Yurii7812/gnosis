# Gnosis のインストーラー（Windows 10 / 11）。
#
#   git clone https://github.com/Yurii7812/gnosis.git
#   cd gnosis
#   powershell -ExecutionPolicy Bypass -File install\install.ps1
#
# 行うこと（ふだんの _vimrc・vimfiles は読まない・変えない）:
#   1. 必要なもの（Vim・Git・Python・fzf・ripgrep、アプリ用に Node.js）を確かめ、無ければ winget で入れる
#   2. Gnosis ホーム（%APPDATA%\Gnosis）に、Gnosis 専用の vimrc とプラグイン領域を作る
#   3. アプリ（Electron）を入れる（npm install・node-pty の作り直し・build）
#   4. デスクトップとスタートメニューに、アイコン付きのショートカット「Gnosis」を作る
# オプション: -Yes（確認しない） -NoSystem（winget で入れない） -NoApp（アプリを入れない）
param([switch]$Yes, [switch]$NoSystem, [switch]$NoApp)
$ErrorActionPreference = 'Stop'
$GnosisDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$GnosisHome = if ($env:GNOSIS_HOME) { $env:GNOSIS_HOME } else { Join-Path $env:APPDATA 'Gnosis' }
$Ja = (Get-Culture).Name -like 'ja*'
function Say([string]$ja, [string]$en) { if ($Ja) { Write-Host $ja } else { Write-Host $en } }
function Step([string]$ja, [string]$en) { Write-Host ''; if ($Ja) { Write-Host "== $ja" } else { Write-Host "== $en" } }
function Ask([string]$ja, [string]$en) {
  if ($Yes) { return $true }
  $q = if ($Ja) { $ja } else { $en }
  $a = Read-Host "$q [Y/n]"
  return -not ($a -match '^(n|no)$')
}
function Have([string]$name) { return [bool](Get-Command $name -ErrorAction SilentlyContinue) }
function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}
function Find-Vim([string]$name) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $bases = @($env:ProgramFiles, ${env:ProgramFiles(x86)})
  if ($env:LOCALAPPDATA) { $bases += (Join-Path $env:LOCALAPPDATA 'Programs') }
  foreach ($base in $bases) {
    if (-not $base) { continue }
    $f = Get-ChildItem -Path (Join-Path $base 'Vim') -Filter $name -Recurse -Depth 2 -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
    if ($f) { return $f.FullName }
  }
  return $null
}
function Vim-Ok([string]$exe) {
  if (-not $exe) { return $false }
  $v = & $exe --version 2>$null | Select-Object -First 40 | Out-String
  foreach ($f in 'job', 'channel', 'timers', 'textprop', 'popupwin') { if ($v -notmatch "\+$f") { return $false } }
  return $true
}

# ---------------------------------------------------------------- 1. 必要なもの
Step '必要なものを確かめます' 'Checking requirements'
$need = @()
$vim = Find-Vim 'vim.exe'
if (Vim-Ok $vim) { Say "  Vim: $vim（使えます。ふだんの設定は読み込みません）" "  Vim: $vim (usable; your own Vim settings are not loaded)" } else { $need += @{ id = 'vim.vim'; name = 'Vim' } }
if (-not (Have 'git')) { $need += @{ id = 'Git.Git'; name = 'Git' } }
if (-not ((Have 'py') -or (Have 'python'))) { $need += @{ id = 'Python.Python.3.12'; name = 'Python' } }
if (-not (Have 'fzf')) { $need += @{ id = 'junegunn.fzf'; name = 'fzf' } }
if (-not (Have 'rg')) { $need += @{ id = 'BurntSushi.ripgrep.MSVC'; name = 'ripgrep' } }
if (-not $NoApp -and -not (Have 'npm')) { $need += @{ id = 'OpenJS.NodeJS.LTS'; name = 'Node.js' } }
if ($need.Count -gt 0) {
  Say ('  足りないもの: ' + (($need | ForEach-Object { $_.name }) -join ', ')) ('  Missing: ' + (($need | ForEach-Object { $_.name }) -join ', '))
  if (-not $NoSystem -and (Have 'winget') -and (Ask '  winget で入れますか？' '  Install them with winget?')) {
    foreach ($p in $need) {
      winget install --id $p.id -e --silent --accept-package-agreements --accept-source-agreements
    }
    Refresh-Path
  } else {
    Say '  winget では入れません。' '  Not installing with winget.'
  }
}
$vim = Find-Vim 'vim.exe'
if (-not (Vim-Ok $vim)) {
  Say 'Gnosis に使える Vim（+job +channel +timers +textprop +popupwin）が見つかりません。https://www.vim.org/download.php から入れてから、もう一度実行してください。' 'No usable Vim found. Install it from https://www.vim.org/download.php and run again.'
  exit 1
}
if (-not (Have 'git')) { Say 'Git が必要です。' 'Git is required.'; exit 1 }

# ---------------------------------------------------------------- 2. Gnosis 専用の Vim 環境
Step "Gnosis 専用の Vim 環境を作ります: $GnosisHome" "Creating the Gnosis-only Vim environment: $GnosisHome"
foreach ($d in 'plugins', 'themes', 'state', 'logs') { New-Item -ItemType Directory -Force -Path (Join-Path $GnosisHome $d) | Out-Null }
$plugins = @(@('fzf', 'junegunn/fzf'), @('fzf.vim', 'junegunn/fzf.vim'), @('vim-surround', 'tpope/vim-surround'))
foreach ($p in $plugins) {
  $dst = Join-Path $GnosisHome ('plugins\' + $p[0])
  if (Test-Path (Join-Path $dst '.git')) { git -C $dst pull --ff-only --quiet }
  elseif ($env:GNOSIS_PLUGIN_MIRROR) { git clone --quiet --depth 1 (Join-Path $env:GNOSIS_PLUGIN_MIRROR $p[0]) $dst }
  else { git clone --quiet --depth 1 ("https://github.com/" + $p[1] + ".git") $dst }
  Say "  プラグイン: $($p[0])" "  plugin: $($p[0])"
}
$vimrcSrc = (Join-Path $GnosisDir 'vimrc_gnosis') -replace "'", "''"
$vimrc = @"
" Gnosis 専用の vimrc（インストーラーが作成。もう一度インストールすると作り直す）。
" この Vim は、ふだんの _vimrc・vimfiles を読まない。Gnosis だけの追加設定は vimrc.local に書く。
execute 'source ' . fnameescape('$vimrcSrc')
"@
[IO.File]::WriteAllText((Join-Path $GnosisHome 'vimrc'), $vimrc, (New-Object Text.UTF8Encoding $false))
Say "  vimrc: $(Join-Path $GnosisHome 'vimrc')" "  vimrc: $(Join-Path $GnosisHome 'vimrc')"
$py = if (Have 'py') { 'py' } elseif (Have 'python') { 'python' } else { $null }
if ($py) {
  & $py -m pip install --user --quiet pykakasi 2>$null
  if ($LASTEXITCODE -ne 0) { Say '  pykakasi は入れませんでした（よみ順は文字コード順になります）' '  pykakasi not installed (sorting by reading falls back to code order)' }
}

# ---------------------------------------------------------------- 3. アプリ
$electron = Join-Path $GnosisDir 'web\node_modules\electron\dist\electron.exe'
if (-not $NoApp) {
  Step 'アプリ（Electron）を入れます' 'Installing the app (Electron)'
  if (Have 'npm') {
    Push-Location (Join-Path $GnosisDir 'web')
    try {
      npm install --no-audit --no-fund
      npm run rebuild:pty
      npm run build
    } catch { Say '  アプリを入れられませんでした。gvim で使えます。' '  Could not install the app; Gnosis still works in gvim.' }
    Pop-Location
  } else { Say '  Node.js が無いのでアプリは入れません。' '  No Node.js; skipping the app.' }
}

# ---------------------------------------------------------------- 4. ショートカット
Step 'ショートカットを作ります' 'Creating shortcuts'
$icon = Join-Path $GnosisDir 'assets\icons\gnosis.ico'
$shell = New-Object -ComObject WScript.Shell
$targets = @((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Gnosis.lnk'), (Join-Path ([Environment]::GetFolderPath('Programs')) 'Gnosis.lnk'))
foreach ($lnkPath in $targets) {
  $lnk = $shell.CreateShortcut($lnkPath)
  if (Test-Path $electron) {
    $lnk.TargetPath = $electron
    $lnk.Arguments = '"' + (Join-Path $GnosisDir 'web') + '"'
  } else {
    $gvim = Find-Vim 'gvim.exe'
    $lnk.TargetPath = $gvim
    $lnk.Arguments = '-u "' + (Join-Path $GnosisHome 'vimrc') + '" -U NONE'
  }
  $lnk.WorkingDirectory = $GnosisDir
  $lnk.IconLocation = $icon
  $lnk.Description = 'Gnosis'
  $lnk.Save()
  Say "  $lnkPath" "  $lnkPath"
}
# 端末から gnosis で起動できるように（ユーザーの PATH に bin を足す）
$bin = Join-Path $GnosisDir 'bin'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $bin) {
  [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $bin), 'User')
  Say "  PATH に追加: $bin" "  added to PATH: $bin"
}
# アプリが Vim を見つけられるように（PATH に vim.exe が無いことがある）
[Environment]::SetEnvironmentVariable('GNOSIS_VIM', (Find-Vim 'vim.exe'), 'User')

Step '完了' 'Done'
Say '  デスクトップかスタートメニューの「Gnosis」で起動します。ふだんの Vim の設定は変えていません。' '  Start Gnosis from the "Gnosis" icon on the desktop or Start menu. Your normal Vim settings were not changed.'
