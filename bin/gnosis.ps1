# Gnosis のランチャー（Windows）。bin\gnosis.cmd から呼ぶ。
#   gnosis              アプリ（Electron）で起動。無ければ GUI 版 Vim（gvim）
#   gnosis --app        アプリで起動
#   gnosis --gui        gvim で起動
#   gnosis --tui        今のコンソールの Vim で起動
#   gnosis --where      Gnosis のフォルダ・Gnosis ホーム・使う vimrc を表示
# Vim は Gnosis 専用の vimrc（%APPDATA%\Gnosis\vimrc。無ければ本体の vimrc_gnosis）で起動する。
# ふだんの _vimrc・vimfiles は読まない・変えない。
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
$ErrorActionPreference = 'Stop'
$GnosisDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$env:GNOSIS_DIR = $GnosisDir
if (-not $env:GNOSIS_HOME) { $env:GNOSIS_HOME = Join-Path $env:APPDATA 'Gnosis' }
if ($env:GNOSIS_VIMRC) { $Vimrc = $env:GNOSIS_VIMRC }
elseif (Test-Path (Join-Path $env:GNOSIS_HOME 'vimrc')) { $Vimrc = Join-Path $env:GNOSIS_HOME 'vimrc' }
else { $Vimrc = Join-Path $GnosisDir 'vimrc_gnosis' }
$env:GNOSIS_VIMRC = $Vimrc

function Find-VimExe([string]$name) {
  if ($env:GNOSIS_VIM -and $name -eq 'vim.exe') { return $env:GNOSIS_VIM }
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $bases = @($env:ProgramFiles, ${env:ProgramFiles(x86)})
  if ($env:LOCALAPPDATA) { $bases += (Join-Path $env:LOCALAPPDATA 'Programs') }
  foreach ($base in $bases) {
    if (-not $base) { continue }
    $found = Get-ChildItem -Path (Join-Path $base 'Vim') -Filter $name -Recurse -Depth 2 -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
    if ($found) { return $found.FullName }
  }
  return $null
}

$Electron = Join-Path $GnosisDir 'web\node_modules\electron\dist\electron.exe'
$mode = 'auto'
if ($Rest -and $Rest.Count -gt 0) {
  switch ($Rest[0]) {
    '--app' { $mode = 'app'; $Rest = $Rest[1..($Rest.Count)] }
    '--gui' { $mode = 'gui'; $Rest = $Rest[1..($Rest.Count)] }
    '--tui' { $mode = 'tui'; $Rest = $Rest[1..($Rest.Count)] }
    '--terminal' { $mode = 'tui'; $Rest = $Rest[1..($Rest.Count)] }
    '--where' {
      "Gnosis: $GnosisDir"; "Gnosis home: $env:GNOSIS_HOME"; "vimrc: $Vimrc"; "vim: $(Find-VimExe 'vim.exe')"; exit 0
    }
  }
}
$Rest = @($Rest | Where-Object { $_ })
$vim = Find-VimExe 'vim.exe'
if ($vim) { $env:GNOSIS_VIM = $vim }

if ($mode -eq 'auto') { $mode = if (Test-Path $Electron) { 'app' } else { 'gui' } }
switch ($mode) {
  'app' {
    if (-not (Test-Path $Electron)) { Write-Error 'Gnosis: アプリが入っていません。install\install.ps1 を実行してください / the app is not installed' }
    if ($Rest.Count -ge 1 -and (Test-Path $Rest[0])) { $env:GNOSIS_FILE = (Resolve-Path $Rest[0]).Path }
    Start-Process -FilePath $Electron -ArgumentList @("`"$GnosisDir\web`"") -WorkingDirectory $GnosisDir
  }
  'gui' {
    $gvim = Find-VimExe 'gvim.exe'
    if (-not $gvim) { Write-Error 'Gnosis: gvim.exe が見つかりません / gvim.exe not found' }
    $args2 = @('-u', "`"$Vimrc`"", '-U', 'NONE') + ($Rest | ForEach-Object { "`"$_`"" })
    Start-Process -FilePath $gvim -ArgumentList $args2
  }
  'tui' {
    if (-not $vim) { Write-Error 'Gnosis: vim.exe が見つかりません / vim.exe not found' }
    & $vim -u $Vimrc @Rest
  }
}
