@echo off
rem ============================================================
rem  egg-runner  ->  open in the Godot editor
rem
rem  Opening the project here also registers it in Godot's
rem  project manager, so it will show up in the project list
rem  the next time you launch Godot normally.
rem ============================================================
setlocal
set "GODOT=H:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
set "PROJ=%~dp0"
set "PROJ=%PROJ:~0,-1%"

rem Pin the working directory (the save folder used to drift with it).
cd /d "%PROJ%"

if not exist "%GODOT%" (
    echo [ERROR] Godot executable not found:
    echo         %GODOT%
    pause
    exit /b 1
)
if not exist "%PROJ%\project.godot" (
    echo [ERROR] project.godot not found in:
    echo         %PROJ%
    pause
    exit /b 1
)

echo Opening project in Godot editor...
echo   project : %PROJ%
echo.
"%GODOT%" --path "%PROJ%" --editor
