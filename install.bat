@echo off
rem Skyrim Modding Assistant - runs the installer elevated, ExecutionPolicy Bypass for this one process only.
powershell.exe -NoProfile -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0install-skyrim-modding-tools.ps1\"'"
