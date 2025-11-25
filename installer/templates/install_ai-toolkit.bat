:: Modified installer of AI-Toolkit
:: Original source: https://github.com/Tavris1/AI-Toolkit-Easy-Install under MIT by ivo

@Echo off
cd /D %~dp0
set ROOT=%CD%

:: tested AITOOLGITCOMMITs: 21bb8a2bf4e3ac08fe89d628e9cc7b3fcf759a65 c6edd71 3086a58
set AITOOLGITCOMMIT=c6edd71
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
git.exe checkout %AITOOLGITCOMMIT%
cd %ROOT%\AI-Toolkit
robocopy ai-toolkit .  /s /e /MOV
RMDIR /S/Q ai-toolkit
cd %ROOT%\AI-Toolkit\python_embeded
curl.exe -OL https://github.com/woct0rdho/triton-windows/releases/download/v3.0.0-windows.post1/python_3.12.7_include_libs.zip --ssl-no-revoke %CURLargs%
tar.exe -xf python_3.12.7_include_libs.zip
erase python_3.12.7_include_libs.zip

cd %ROOT%\AI-Toolkit
:: tsuchinoko11 @ help_me on 17.11.2025:
::..\python_embeded\python.exe -m pip install torch==2.8.0 torchvision==0.23.0 torchaudio==2.8.0 --index-url https://download.pytorch.org/whl/nightly/cu128
python.exe -m pip install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu128
python.exe -m pip install poetry-core
python.exe -m pip install triton-windows==3.4.0.post20
python.exe -m pip install --upgrade triton-windows
python.exe -m pip install hf_xet
cd %ROOT%\AI-Toolkit
python.exe -m pip install -r .\requirements.txt

cd..\
echo.
goto :eof


:create_bat_files
goto :eof