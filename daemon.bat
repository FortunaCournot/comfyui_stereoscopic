::====================================================================
:: VR we are - (C)2025 Fortuna Cournot, https://www.3d-gallery.org/
:: Daemon starter
::====================================================================
ECHO OFF 
:: Windows version check 
IF NOT "%OS%"=="Windows_NT" GOTO Fail
:: Keep variable local 
SETLOCAL enabledelayedexpansion


:: CheckOS
FOR /f "tokens=4-5 delims=. " %%i IN ('ver') DO SET VERSION=%%i.%%j
IF "%version%" == "6.3" ECHO Windows 8.1 not supported
IF "%version%" == "6.2" ECHO Windows 8 not supported.
IF "%version%" == "6.1" ECHO Windows 7 not supported.
IF "%version%" == "6.0" ECHO Windows Vista not supported.
IF "%version%" == "10.0" GOTO CheckArch
ECHO OS version %version%
GOTO Fail

:CheckArch
reg Query "HKLM\Hardware\Description\System\CentralProcessor\0" | find /i "x86" > NUL && set OS=32BIT || set OS=64BIT
if %OS%==32BIT echo This is a 32bit operating system. Not supported.
if %OS%==64BIT GOTO CheckGit
echo OS Architecture %OS%
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
                echo Found Git at "!GIT!".
                goto FOUND
            )
        )
    )
)
goto NOT_FOUND

:FOUND
:: Make sure Bash is in PATH (for running scripts).
SET PATH=%GIT%bin;%PATH%
git --version
IF %ERRORLEVEL% == 0 GOTO Start
ECHO Git version to old. Please update.
GOTO Fail

:NOT_FOUND
ECHO Please install Git version 2.37 or later from https://git-scm.com/
Goto Fail

:: Execute daemon shell script
:Start
ECHO ON
"%GIT%"git-bash.exe daemon.sh
IF %ERRORLEVEL% == 0 GOTO End

:Fail 
ECHO Start failed. (%ERRORLEVEL%)
GOTO End

:: Done 
:End
ENDLOCAL

