@echo off
rem Windows: double-click to start DeCodeDNA.
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0lib\launcher.ps1" %*
if errorlevel 1 pause
