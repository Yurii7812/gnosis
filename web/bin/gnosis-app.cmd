@echo off
rem 旧名（互換）: Gnosis のランチャー bin\gnosis.cmd --app を呼ぶ。
if not "%~1"=="" for %%I in ("%~1") do set "GNOSIS_ROOT=%%~fI"
call "%~dp0..\..\bin\gnosis.cmd" --app
