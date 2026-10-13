@echo off
rem Gnosis のランチャー（Windows）。中身は gnosis.ps1。
rem   gnosis [--app | --gui | --tui | --where] [ノート.md]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gnosis.ps1" %*
