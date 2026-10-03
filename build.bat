@echo off
python tools\build.py
if errorlevel 1 exit /b 1
echo ROM: dist\samirius_arena.gg
