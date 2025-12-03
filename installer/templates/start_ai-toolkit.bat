@echo off

set "local_serv=http://localhost:8675"

cd /D %~dp0

cd AI-Toolkit\
set ROOT=%CD%
set PATH=%ROOT%\python_embeded\;%ROOT%\python_embeded\Scripts\;%PATH%
set TOOLKIT_PYTHON_PATH=%ROOT%\python_embeded\python.exe

cd .\ui
start cmd.exe /k npm run build_and_start
:::loop
::@powershell -Command "try { $response = Invoke-WebRequest -Uri '!local_serv!' -TimeoutSec 2 -UseBasicParsing; exit 0 } catch { exit 1 }" >nul 2>&1
::@if !errorlevel! neq 0 (timeout /t 2 /nobreak >nul&&goto :loop)
::@start !local_serv!

cd %ROOT%\..
