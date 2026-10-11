@echo off
rem simple_yurii_note デスクトップアプリ (Electron) を Windows で起動する。
rem 使い方: simple-yurii-note-app.cmd [VAULT_DIR]
rem   VAULT_DIR を省略すると、Vim（SYN）が前回使った root を使う。
rem 初回だけ: npm install && npm run rebuild:pty
set "WEB=%~dp0.."
set "EXE=%WEB%\node_modules\electron\dist\electron.exe"
if not exist "%EXE%" (
  echo electron が見つかりません。次を実行してください: cd "%WEB%" ^&^& npm install
  exit /b 1
)
if not "%~1"=="" for %%I in ("%~1") do set "PKM_ROOT=%%~fI"
"%EXE%" "%WEB%" --no-sandbox
