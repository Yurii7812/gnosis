#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$entry = Join-Path $root 'install\install.ps1'
$runner = Join-Path $root 'install\install-windows.ps1'

# Windows PowerShell 5.1 does not reliably read BOM-less UTF-8 source with
# non-ASCII literals. Both setup scripts deliberately use ASCII-only text.
foreach ($file in @($entry, $runner)) {
    $bytes = [System.IO.File]::ReadAllBytes($file)
    if (@($bytes | Where-Object { $_ -gt 127 }).Count -ne 0) {
        throw "Non-ASCII PowerShell 5.1 source: $file"
    }
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $file, [ref]$tokens, [ref]$errors
    ) | Out-Null
    if ($errors.Count -gt 0) {
        throw ('PowerShell 5.1 parse errors in ' + $file + ': ' + ($errors | Out-String))
    }
}
Write-Host 'OK: both Windows scripts parse in Windows PowerShell 5.1'

# Verify the documented install.ps1 entrypoint without enabling WSL or
# modifying any Windows settings. Replace its target with an isolated stub.
$tmp = Join-Path $env:TEMP ('gnosis-install-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    Copy-Item -LiteralPath $entry -Destination (Join-Path $tmp 'install.ps1')
    @'
param([switch]$SkipInstall, [switch]$NoShortcut)
if (-not $SkipInstall -or -not $NoShortcut) {
    throw 'The wrapper did not forward the options.'
}
[System.IO.File]::WriteAllText(
    (Join-Path $PSScriptRoot 'invoked.txt'),
    'safe',
    [System.Text.Encoding]::ASCII
)
'@ | Set-Content -LiteralPath (Join-Path $tmp 'install-windows.ps1') -Encoding Ascii
    & (Join-Path $tmp 'install.ps1') -NoSystem -NoShortcut -NoApp
    if (-not (Test-Path -LiteralPath (Join-Path $tmp 'invoked.txt'))) {
        throw 'The canonical install.ps1 did not invoke the Windows installer.'
    }
    Write-Host 'OK: documented installer entrypoint delegates safely'
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
