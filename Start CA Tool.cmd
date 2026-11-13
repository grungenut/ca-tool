@echo off
rem Double-click to start the C/A Tool. Uses the PowerShell built into Windows; nothing to install.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0CATool.ps1"
