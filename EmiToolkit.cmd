@echo off
rem ====================================================================
rem  Another's Toolbox - lanzador
rem  Ejecuta EmiToolkit.ps1 con -File y la ruta entre comillas dobles:
rem  la ruta nunca va dentro de un texto -Command, asi que un apostrofo
rem  (C:\Users\O'Brien), un & o unos parentesis en la ruta no la rompen.
rem  La elevacion (UAC) la hace el propio EmiToolkit.ps1.
rem  Logs: Data\launcher.log y Data\runtime-error.log
rem ====================================================================
setlocal
set "HERE=%~dp0"
set "PS1=%HERE%EmiToolkit.ps1"
rem El log va al perfil del usuario: en %ProgramFiles% la carpeta de la app no es escribible sin elevar
set "LOGDIR=%LOCALAPPDATA%\EmiToolkit"

rem Crear carpeta Data si no existe
if not exist "%LOGDIR%" mkdir "%LOGDIR%"

rem Registrar lanzamiento (las rutas siempre entre comillas)
>>"%LOGDIR%\launcher.log" echo [%date% %time%] === ANOTHER'S TOOLBOX LAUNCHER (CMD) ===
>>"%LOGDIR%\launcher.log" echo User: "%USERNAME%"
>>"%LOGDIR%\launcher.log" echo Path: "%PS1%"

rem Verificar que el script existe. El aviso lee la ruta de la variable de
rem entorno PS1, no de un texto pegado en el comando.
if not exist "%PS1%" (
    >>"%LOGDIR%\launcher.log" echo [FATAL] EmiToolkit.ps1 no encontrado en: "%PS1%"
    powershell.exe -NoProfile -Command "Add-Type -AssemblyName PresentationFramework; [void][System.Windows.MessageBox]::Show('No se encontro EmiToolkit.ps1 en:' + [Environment]::NewLine + $env:PS1, 'Another''s Toolbox', 'OK', 'Error')"
    exit /b 1
)

rem -STA es necesario para WPF; EmiToolkit.ps1 se relanza elevado si hace falta
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%PS1%" >>"%LOGDIR%\launcher.log" 2>&1

>>"%LOGDIR%\launcher.log" echo [%date% %time%] Launch complete (codigo %errorlevel%)
>>"%LOGDIR%\launcher.log" echo ============================================================

endlocal
