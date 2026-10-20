@echo off
rem Eksporterer web-bygget og starter serveren med HTTPS, slik at alle paa wifi kan spille.
rem   scripts\web.cmd          eksporter + start server (stopp med Ctrl+C)
rem   scripts\web.cmd export   bare eksporter
rem Godot hentes fra miljoevariabelen GODOT, ellers fra Nedlastinger-mappen.
setlocal
if "%GODOT%"=="" set "GODOT=%USERPROFILE%\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe"
if not exist "%GODOT%" (
	echo Fant ikke Godot: %GODOT%
	echo Sett miljoevariabelen GODOT til stien til Godot_v4.7-stable_win64_console.exe
	exit /b 1
)
cd /d "%~dp0.."
if not exist build\web mkdir build\web

echo Eksporterer web-bygget ...
"%GODOT%" --headless --path . --export-release "Web" build/web/index.html >build\export.log 2>&1
if not exist build\web\index.wasm (
	echo Eksporten feilet. Se build\export.log
	exit /b 1
)
echo Ferdig: build\web
if /i "%~1"=="export" exit /b 0

"%GODOT%" --headless --path . -- --server --web build/web --https
