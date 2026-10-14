# Gnosis one-command installer for Windows (Windows PowerShell 5.1 or PowerShell 7).
# ASCII-only. Run from PowerShell:
#   irm https://raw.githubusercontent.com/Yurii7812/gnosis/main/install/bootstrap.ps1 | iex
#
# What it does: resolves the requested ref (default: main) to ONE exact commit over HTTPS,
# downloads that commit's archive from GitHub, checks the archive really contains that
# commit, unpacks it under %LOCALAPPDATA%\Gnosis\installer and runs install-windows.ps1.
# Pin a version:  $env:GNOSIS_REF = 'v1.0.0'   (a tag or branch name) before running.
# Nothing is installed until you answer the prompts in install-windows.ps1.
$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
$ProgressPreference = 'SilentlyContinue'
$owner = 'Yurii7812'; $repo = 'gnosis'
$ref = if ($env:GNOSIS_REF) { $env:GNOSIS_REF } else { 'main' }
if ($ref -notmatch '^[A-Za-z0-9._/-]+$') { throw 'GNOSIS_REF contains unexpected characters.' }
$root = Join-Path $env:LOCALAPPDATA 'Gnosis'
$work = Join-Path $root 'download'
New-Item -ItemType Directory -Force -Path $work | Out-Null

function Get-Web([string]$url, [string]$outFile) {
  $last = $null
  foreach ($i in 1..3) {
    try {
      Invoke-WebRequest -Uri $url -OutFile $outFile -UseBasicParsing -Headers @{ 'User-Agent' = 'gnosis-installer' }
      return
    } catch { $last = $_; Start-Sleep -Seconds (2 * $i) }
  }
  throw ('Download failed (check your internet connection / proxy): ' + $url + ' - ' + $last.Exception.Message)
}

Write-Host ('Gnosis installer: resolving ' + $ref + ' ...')
$shaFile = Join-Path $work 'sha.txt'
$sha = $null
if ($ref -match '^[0-9a-f]{40}$') { throw 'Pin a tag or branch name (GNOSIS_REF); a bare commit id cannot be checked out inside Ubuntu by this installer.' }
try {
    Invoke-WebRequest -UseBasicParsing -OutFile $shaFile -Uri ('https://api.github.com/repos/' + $owner + '/' + $repo + '/commits/' + $ref) -Headers @{ 'User-Agent' = 'gnosis-installer'; 'Accept' = 'application/vnd.github.sha' }
    $sha = ([IO.File]::ReadAllText($shaFile)).Trim()
  } catch {
    throw ('Could not resolve "' + $ref + '" on GitHub (offline, rate limit, or no such ref): ' + $_.Exception.Message)
}
if ($sha -notmatch '^[0-9a-f]{40}$') { throw 'GitHub returned an unexpected commit id.' }

$zip = Join-Path $work ('gnosis-' + $sha + '.zip')
Get-Web ('https://codeload.github.com/' + $owner + '/' + $repo + '/zip/' + $sha) $zip
Add-Type -AssemblyName System.IO.Compression.FileSystem
$extract = Join-Path $work ('x-' + $sha)
if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
[IO.Compression.ZipFile]::ExtractToDirectory($zip, $extract)
$top = @(Get-ChildItem -LiteralPath $extract -Directory)
# The archive's top folder is <repo>-<commit>; refuse anything that does not match.
if ($top.Count -ne 1 -or $top[0].Name -ne ($repo + '-' + $sha)) { throw 'Downloaded archive does not match the requested commit.' }
$installDir = Join-Path $top[0].FullName 'install'
$installer = Join-Path $installDir 'install-windows.ps1'
if (-not (Test-Path -LiteralPath $installer)) { throw 'The downloaded archive has no Windows installer.' }

Write-Host ('Gnosis installer: commit ' + $sha)
$argv = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$installer)
if ($env:GNOSIS_REF) { $argv += @('-Ref',$ref) }
& powershell.exe @argv
$code = $LASTEXITCODE
Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
if ($code -ne 0) { throw ('Gnosis installation did not complete (exit ' + $code + '). See ' + (Join-Path $root 'install.log')) }
