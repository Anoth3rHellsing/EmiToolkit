@echo off
rem ====================================================================
rem  Another's Toolbox - lanzador
rem  Ejecuta AnotherToolbox.ps1 directamente con -File (no -Command).
rem  El launcher .exe usaba -Command que rompia el parsing del XAML.
rem  Auto-elevacion via PowerShell Start-Process -Verb RunAs.
rem  Logs: Data\launcher.log y Data\runtime-error.log
rem ====================================================================
setlocal
set "HERE=%~dp0"
set "PS1=%HERE%AnotherToolbox.ps1"
set "LOGDIR=%HERE%Data"

rem Crear carpeta Data si no existe
if not exist "%LOGDIR%" mkdir "%LOGDIR%"

rem Registrar lanzamiento
echo [%date% %time%] === ANOTHER TOOLBOX LAUNCHER (CMD) === >> "%LOGDIR%\launcher.log"
echo User: %USERNAME% >> "%LOGDIR%\launcher.log"
echo Path: %PS1% >> "%LOGDIR%\launcher.log"

rem Verificar que el script existe
if not exist "%PS1%" (
    echo [FATAL] AnotherToolbox.ps1 no encontrado en: %PS1% >> "%LOGDIR%\launcher.log"
    powershell.exe -NoProfile -Command "[System.Windows.MessageBox]::Show('No se encontro AnotherToolbox.ps1 en:\n%PS1%','Another Toolbox Error','OK','Error')"
    exit /b 1
)

rem Lanzar con elevacion y -File (NO -Command)
rem Start-Process -Verb RunAs pide UAC; -STA es necesario para WPF
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
    "Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-WindowStyle','Hidden','-File','\"%PS1%\"') -WorkingDirectory '%HERE%'" ^
    >> "%LOGDIR%\launcher.log" 2>&1

echo [%date% %time%] Launch complete >> "%LOGDIR%\launcher.log"
echo ============================================================ >> "%LOGDIR%\launcher.log"

endlocal
