@echo off
rem ============================================================
rem  egg-runner  launcher  (double-click to play)
rem
rem  Why this file exists:
rem    The project path contains spaces, and passing an absolute
rem    path to Godot directly gets truncated at the space
rem    ("Invalid project path specified"). Using %~dp0 plus
rem    quoting keeps it intact.
rem ============================================================
setlocal
set "GODOT=H:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
set "PROJ=%~dp0"
set "PROJ=%PROJ:~0,-1%"

rem Pin the working directory. The save folder used to drift with the
rem working directory, so launching from elsewhere showed an empty save.
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

echo Starting egg-runner...
echo   engine  : %GODOT%
echo   project : %PROJ%
echo.
"%GODOT%" --path "%PROJ%" --resolution 1280x720
