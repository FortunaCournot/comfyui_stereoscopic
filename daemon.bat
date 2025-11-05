::====================================================================
:: VR we are - (C)2025 Fortuna Cournot, https://www.3d-gallery.org/
:: Daemon starter
::====================================================================
@ECHO OFF 
:: Windows version check 
IF NOT "%OS%"=="Windows_NT" GOTO Fail
:: Keep variable local 
SETLOCAL enabledelayedexpansion


:: CheckOS
FOR /f "tokens=4-5 delims=. " %%i IN ('ver') DO SET VERSION=%%i.%%j
IF "%VERSION%" == "6.3" ECHO Windows 8.1 not supported
IF "%VERSION%" == "6.2" ECHO Windows 8 not supported.
IF "%VERSION%" == "6.1" ECHO Windows 7 not supported.
IF "%VERSION%" == "6.0" ECHO Windows Vista not supported.
IF "%VERSION%" == "10.0" GOTO CheckArch
ECHO OS-Version: %VERSION%
ver
GOTO Fail

:CheckArch
reg Query "HKLM\Hardware\Description\System\CentralProcessor\0" | find /i "x86" > NUL && set OS2=32BIT || set OS2=64BIT
if %OS2%==32BIT echo [91mThis is a 32bit operating system. Not supported.[0m
if %OS2%==64BIT GOTO CheckGit
echo OS Architecture: %OS2%
GOTO Fail

:CheckGit
CLS
ECHO/
ECHO === VR we are - Starting daemon ===
ECHO/
:: Read the Git for Windows installation path from the Registry.
for %%k in (HKCU HKLM) do (
    for %%w in (\ \Wow6432Node\) do (
        for /f "skip=2 delims=: tokens=1*" %%a in ('reg query "%%k\SOFTWARE%%wMicrosoft\Windows\CurrentVersion\Uninstall\Git_is1" /v InstallLocation 2^> nul') do (
            for /f "tokens=3" %%z in ("%%a") do (
                set GIT=%%z:%%b
                ::echo Found Git at "!GIT!".
                goto FOUND
            )
        )
    )
)
ECHO [91mGit not found. Please install from [96m https://git-scm.com/ [0m
GOTO Fail

:FOUND
:: Make sure Bash is in PATH (for running scripts).
SET PATH=%GIT%bin;%PATH%
git --version
IF %ERRORLEVEL% == 0 GOTO Start
ECHO * [91mGit to old (version is below 2.37), you need to update before using VR we are.[0m
ECHO   [91mPlease download Git from [96m https://git-scm.com/ [0m
GOTO Fail


:: Execute daemon shell script
:Start
ECHO ON
"%GIT%"git-bash.exe daemon.sh
IF %ERRORLEVEL% == 0 GOTO End
ECHO [91mError level: %ERRORLEVEL%[0m

:Fail 
ECHO OS: %OS%
ECHO [91mDaemon start failed.[0m
pause
GOTO End

:: Done 
:End
ENDLOCAL

