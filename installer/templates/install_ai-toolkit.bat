:: Modified installer of AI-Toolkit
:: Original source: https://github.com/Tavris1/AI-Toolkit-Easy-Install under MIT by ivo

@Echo off
cd %~dp0
set ROOT="%CD%"

:: tested AITOOLGITCOMMITs: c6edd71 3086a58
set AITOOLGITCOMMITs=c6edd71
set "version_title=AI-Toolkit-Easy-Install v0.3.21 by ivo (modified version by FortunaCournot)"
Title %version_title%

rem Standard: interactiv
set "NONINTERACTIVE=0"
for %%A in (%*) do (
  if /I "%%~A"=="/NONINTERACTIVE" set "NONINTERACTIVE=1"
  if /I "%%~A"=="-noninteractive" set "NONINTERACTIVE=1"
  if /I "%%~A"=="/NI" set "NONINTERACTIVE=1"
)

:: Set colors ::
call :set_colors

:: Set arguments ::
set "PIPargs=--no-cache-dir --no-warn-script-location --timeout=1000 --retries 200"
set "CURLargs=--retry 200 --retry-all-errors"
set "UVargs=--no-cache --link-mode=copy"

:: Set local path only (temporarily) ::
for /f "delims=" %%G in ('cmd /c "where git.exe 2>nul"') do (set "GIT_PATH=%%~dpG")
for /f "delims=" %%G in ('cmd /c "where node.exe 2>nul"') do (set "NODE_PATH=%%~dpG")
set "path=%GIT_PATH%;%NODE_PATH%"

if exist %windir%\system32 set "path=%PATH%;%windir%\System32"
if exist %windir%\system32\WindowsPowerShell\v1.0 set "path=%PATH%;%windir%\system32\WindowsPowerShell\v1.0"
if exist %localappdata%\Microsoft\WindowsApps set "path=%PATH%;%localappdata%\Microsoft\WindowsApps"

:: Check for Existing AI-Toolkit Folder ::
if exist AI-Toolkit (
	echo %warning%WARNING:%reset% '%bold%AI-Toolkit%reset%' folder already exists!
	echo %green%Move this file to another folder and run it again.%reset%
	echo Press any key to Exit...&Pause>nul
	goto :eof
)

:: Capture the start time ::
for /f %%i in ('powershell -command "Get-Date -Format HH:mm:ss"') do set start=%%i

:: Skip downloading LFS (Large File Storage) files ::
set GIT_LFS_SKIP_SMUDGE=1


::----------------------------------------------------

:: System folder? ::
md AI-Toolkit
if not exist AI-Toolkit (
	cls
	echo %warning%WARNING:%reset% Cannot create folder %yellow%AI-Toolkit%reset%
	echo Make sure you are NOT using system folders like %yellow%Program Files, Windows%reset% or system root %yellow%C:\%reset%
	echo %green%Move this file to another folder and run it again.%reset%
	echo Press any key to Exit...&Pause>nul
	exit /b
)

:: Install Node.js ::
call :nodejs_install

:: Install Python & pip embedded ::
call :python_embedded_install

:: Install AI-Toolkit ::
call :ai-toolkit_install

if "%NONINTERACTIVE%"=="1" (
  goto :finalmessage
)

:: Create 'Start-AI-Toolkit.bat' ::
call :create_bat_files

:: Clear Pip and uv Cache ::
call :clear_pip_uv_cache

:: Capture the end time ::
:set_colors
for /f %%i in ('powershell -command "Get-Date -Format HH:mm:ss"') do set end=%%i
for /f %%i in ('powershell -command "(New-TimeSpan -Start (Get-Date '%start%') -End (Get-Date '%end%')).TotalSeconds"') do set diff=%%i

:: Final Messages ::
:finalmessage
echo.
goto :eof

::::::::::::::::::::::::::::::::: END :::::::::::::::::::::::::::::::::

:set_colors
set warning=[33m
set     red=[91m
set   green=[92m
set  yellow=[93m
set    bold=[1m
set   reset=[0m
goto :eof

:clear_pip_uv_cache
if exist "%localappdata%\pip\cache" rd /s /q "%localappdata%\pip\cache"&&md "%localappdata%\pip\cache"
if exist "%localappdata%\uv\cache" rd /s /q "%localappdata%\uv\cache"&&md "%localappdata%\uv\cache"
echo %green%::::::::::::::: Clearing Pip and uv Cache %yellow%Done%green% :::::::::::::::%reset%
echo.
goto :eof

:install_git
goto :eof

:nodejs_install
:: https://nodejs.org/en
echo %green%::::::::::::::: Installing/Updating%yellow% Node.js %green%:::::::::::::::%reset%
echo.
winget.exe install --id=OpenJS.NodeJS -e
set path=%PATH%;%ProgramFiles%\nodejs
Title %version_title%
echo.
goto :eof

:python_embedded_install
cd %ROOT%\AI-Toolkit
:: https://www.python.org/downloads/release/python-31210/
echo %green%::::::::::::::: Installing%yellow% Python embedded %green%:::::::::::::::%reset%
echo.
curl.exe -OL https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip --ssl-no-revoke %CURLargs%
md python_embeded&&cd python_embeded
tar.exe -xf ..\python-3.12.10-embed-amd64.zip
erase ..\python-3.12.10-embed-amd64.zip
echo.
echo %green%::::::::::::::: Installing%yellow% pip %green%:::::::::::::::%reset%
echo.
curl.exe -sSL https://bootstrap.pypa.io/get-pip.py -o get-pip.py --ssl-no-revoke %CURLargs%

Echo %ROOT%/AI-Toolkit> python312._pth
Echo Lib/site-packages> python312._pth
Echo Lib>> python312._pth
Echo Scripts>> python312._pth
Echo python312.zip>> python312._pth
Echo %CD%>> python312._pth
Echo # import site>> python312._pth
.\python.exe -I get-pip.py %PIPargs%
.\python.exe -I -m pip install --upgrade pip
set PATH=%CD%\;%CD%\Scripts\;%PATH%
cd ..
echo.
goto :eof

:ai-toolkit_install
cd %ROOT%\AI-Toolkit
echo %green%::::::::::::::: Installing%yellow% AI-Toolkit %green%:::::::::::::::%reset%
:: in AI-Toolkit
echo.
git.exe clone https://github.com/ostris/ai-toolkit.git
cd ai-toolkit\
git checkout %AITOOLGITCOMMIT%
cd ..
robocopy ai-toolkit\ .\  /s /e /MOV
:: in AI-Toolkit
cd %ROOT%\AI-Toolkit\python_embeded
curl.exe -OL https://github.com/woct0rdho/triton-windows/releases/download/v3.0.0-windows.post1/python_3.12.7_include_libs.zip --ssl-no-revoke %CURLargs%
tar.exe -xf python_3.12.7_include_libs.zip
erase python_3.12.7_include_libs.zip

:: tsuchinoko11 @ help_me on 17.11.2025:
::..\python_embeded\python.exe -m pip install torch==2.8.0 torchvision==0.23.0 torchaudio==2.8.0 --index-url https://download.pytorch.org/whl/nightly/cu128
python.exe -m pip install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu128
python.exe -m pip install poetry-core
python.exe -m pip install triton-windows==3.4.0.post20
python.exe -m pip install --upgrade triton-windows
python.exe -m pip install hf_xet
python.exe -m pip install -r requirements.txt

cd..\
echo.
goto :eof


:create_bat_files
echo %green%::::::::::::::: Creating%yellow%  Start-AI-Toolkit.bat %green%:::::::::::::::%reset%
::------------------------------------------------
set "start_bat_name=Start-AI-Toolkit.bat"
Echo @echo off^&^&cd /d %%~dp0>%start_bat_name%
Echo Title %version_title%>>%start_bat_name%
Echo setlocal enabledelayedexpansion>>%start_bat_name%
Echo set GIT_LFS_SKIP_SMUDGE=^1>>%start_bat_name%
Echo set "local_serv=http://localhost:8675">>%start_bat_name%
Echo echo.>>%start_bat_name%
Echo cd ./ai-toolkit>>%start_bat_name%
Echo.>>%start_bat_name%

Echo echo ^[92m:::::::::::::: Checking for updates... ::::::::::::::^[0m>>%start_bat_name%
Echo echo.>>%start_bat_name%
Echo git fetch>>%start_bat_name%
Echo git status -uno ^| findstr /C:"Your branch is behind" ^>nul>>%start_bat_name%
Echo if !errorlevel!==0 ^(>>%start_bat_name%
Echo     echo.>>%start_bat_name%
Echo     echo ^[92m::::::::::::::: Installing updates... :::::::::::::::^[0m>>%start_bat_name%
Echo     echo.>>%start_bat_name%
Echo     git pull>>%start_bat_name%
Echo     echo.>>%start_bat_name%
Echo     echo ^[92m::::::::::::: Installing requirements... ::::::::::::^[0m>>%start_bat_name%
Echo     echo.>>%start_bat_name%
Echo     CALL venv\Scripts\activate.bat>>%start_bat_name%
Echo     pip install -r requirements.txt --no-cache>>%start_bat_name%
Echo     CALL venv\Scripts\deactivate.bat>>%start_bat_name%
Echo ^) else ^(>>%start_bat_name%
Echo     echo ^[92m::::::::::::::::: Already up to date ::::::::::::::::^[0m>>%start_bat_name%
Echo     echo.>>%start_bat_name%
Echo ^)>>%start_bat_name%
Echo.>>%start_bat_name%

Echo echo ^[1;93mTips for beginners:^[0m>>%start_bat_name%
Echo echo.>>%start_bat_name%
Echo echo ^[1;93mGeneral:^[0m>>%start_bat_name%
Echo echo  ^[1;32m1.^[0m Set your ^[1;92mHugging Face Token^[0m in Settings>>%start_bat_name%
Echo echo  ^[1;32m2.^[0m Close server with ^[1;92mCtrl+C twice^[0m, not the ^[1;91mX^[0m button>>%start_bat_name%
Echo echo  ^[1;32m3.^[0m To activate the ^[1;92mvirtual environment^[0m (if needed):>>%start_bat_name%
Echo echo     - Open ^[1;92mCMD^[0m where ^[1;92mStart-AI-Toolkit.bat^[0m is located>>%start_bat_name%
Echo echo     - Run ^[1;92mAI-Toolkit\venv\Scripts\activate.bat^[0m>>%start_bat_name%
Echo echo     OR Just start ^[1;92mvenv-AI-Toolkit.bat^[0m>>%start_bat_name%
Echo echo.>>%start_bat_name%
Echo echo ^[1;93mBranches (run CMD in AI-Toolkit folder):^[0m>>%start_bat_name%
Echo echo  ^[1;32m1.^[0m Show current branch: ^[1;92mgit branch^[0m>>%start_bat_name%
Echo echo  ^[1;32m2.^[0m List all branches:   ^[1;92mgit branch -a^[0m>>%start_bat_name%
Echo echo  ^[1;32m3.^[0m Switch branch:       ^[1;92mgit checkout^[0m ^[1;33mbranch_name^[0m>>%start_bat_name%
Echo echo  ^[1;32m4.^[0m Back to ^[1;33mmain^[0m branch: ^[1;92mgit checkout^[0m ^[1;33mmain^[0m>>%start_bat_name%
Echo echo.>>%start_bat_name%
Echo echo ^[92m:::::::: Waiting for the server to start... :::::::::^[0m>>%start_bat_name%
Echo.>>%start_bat_name%

Echo cd ./ui>>%start_bat_name%
Echo set PATH=%PATH%;%PYTHONABS%\;%PYTHONABS%\Scripts\>>%start_bat_name%
Echo start cmd.exe /k npm run build_and_start>>%start_bat_name%
Echo :loop>> %start_bat_name%
Echo powershell -Command "try { $response = Invoke-WebRequest -Uri '!local_serv!' -TimeoutSec 2 -UseBasicParsing; exit 0 } catch { exit 1 }" ^>nul 2^>^&^1>> %start_bat_name%
Echo if !errorlevel! neq 0 ^(timeout /t 2 /nobreak ^>nul^&^&goto :loop^)>> %start_bat_name%
Echo start !local_serv!>> %start_bat_name%
::------------------------------------------------
set "start_bat_name=Start-AI-Toolkit-NoUpdate.bat"
Echo @echo off^&^&cd /d %%~dp0>%start_bat_name%
Echo Title %version_title%>>%start_bat_name%
Echo setlocal enabledelayedexpansion>>%start_bat_name%
Echo set GIT_LFS_SKIP_SMUDGE=^1>>%start_bat_name%
Echo set "local_serv=http://localhost:8675">>%start_bat_name%
Echo echo.>>%start_bat_name%
Echo cd ./ai-toolkit>>%start_bat_name%
Echo.>>%start_bat_name%

Echo echo ^[1;93mTips for beginners:^[0m>>%start_bat_name%
Echo echo.>>%start_bat_name%
Echo echo ^[1;93mGeneral:^[0m>>%start_bat_name%
Echo echo  ^[1;32m1.^[0m Set your ^[1;92mHugging Face Token^[0m in Settings>>%start_bat_name%
Echo echo  ^[1;32m2.^[0m Close server with ^[1;92mCtrl+C twice^[0m, not the ^[1;91mX^[0m button>>%start_bat_name%
Echo echo  ^[1;32m3.^[0m To activate the ^[1;92mvirtual environment^[0m (if needed):>>%start_bat_name%
Echo echo     - Open ^[1;92mCMD^[0m where ^[1;92mStart-AI-Toolkit.bat^[0m is located>>%start_bat_name%
Echo echo     - Run ^[1;92mAI-Toolkit\venv\Scripts\activate.bat^[0m>>%start_bat_name%
Echo echo     OR Just start ^[1;92mvenv-AI-Toolkit.bat^[0m>>%start_bat_name%
Echo echo.>>%start_bat_name%
Echo echo ^[1;93mBranches (run CMD in AI-Toolkit folder):^[0m>>%start_bat_name%
Echo echo  ^[1;32m1.^[0m Show current branch: ^[1;92mgit branch^[0m>>%start_bat_name%
Echo echo  ^[1;32m2.^[0m List all branches:   ^[1;92mgit branch -a^[0m>>%start_bat_name%
Echo echo  ^[1;32m3.^[0m Switch branch:       ^[1;92mgit checkout^[0m ^[1;33mbranch_name^[0m>>%start_bat_name%
Echo echo  ^[1;32m4.^[0m Back to ^[1;33mmain^[0m branch: ^[1;92mgit checkout^[0m ^[1;33mmain^[0m>>%start_bat_name%
Echo echo.>>%start_bat_name%
Echo echo ^[92m:::::::: Waiting for the server to start... :::::::::^[0m>>%start_bat_name%
Echo.>>%start_bat_name%

Echo cd ./ui>>%start_bat_name%
Echo set PATH=%PATH%;%PYTHONABS%\;%PYTHONABS%\Scripts\>>%start_bat_name%
Echo start cmd.exe /k npm run build_and_start>>%start_bat_name%
Echo :loop>> %start_bat_name%
Echo powershell -Command "try { $response = Invoke-WebRequest -Uri '!local_serv!' -TimeoutSec 2 -UseBasicParsing; exit 0 } catch { exit 1 }" ^>nul 2^>^&^1>> %start_bat_name%
Echo if !errorlevel! neq 0 ^(timeout /t 2 /nobreak ^>nul^&^&goto :loop^)>> %start_bat_name%
Echo start !local_serv!>> %start_bat_name%



goto :eof