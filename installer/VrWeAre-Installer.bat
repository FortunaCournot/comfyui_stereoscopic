::====================================================================
:: VR we are - (C)2025 Fortuna Cournot, https://www.3d-gallery.org/
:: Windows Installer
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
ECHO === VR we are - Installation ===
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
:: Do something with Git ...

:NOT_FOUND
ECHO Please install Git version 2.37 or later from https://git-scm.com/
Goto Fail

:Fail 
ECHO Installation failed. (%ERRORLEVEL%)
GOTO End

:: Start Installtion an prompt for ComfyUI base path
:Start
Goto PromptForExisting

:ContinueWithShell
rem CLS
rem ECHO/
rem ECHO === VR we are - Installation ===
ECHO/
ECHO Downloading Git Installer...
rem "%GIT%"git-bash.exe -c 'git curl http://some.url --output some.file ; echo -e $"\n\e[94m=== PRESS RETURN TO CONTINUE ===\e[0m" ; read x'

Goto Fail

:QueryForInstallationType
CHOICE /C YNQ /M "Do you want to use an existing ComfyUI installation (press Q to quit) "
IF %ERRORLEVEL% == 1 GOTO PromptForExisting
IF %ERRORLEVEL% == 2 GOTO PromptForParentPath
GOTO End

:PromptForParentPath
ECHO/
ECHO Please type the parent path of the installation and press ENTER.
ECHO/
ECHO Or alternatively drag ^& drop the folder from Windows
ECHO Explorer on this console window and press ENTER.
ECHO/

SET "InstallFolder=""
SET /P "InstallFolder=Path: "
SET "InstallFolder=%InstallFolder:"=%"
IF "%InstallFolder%" == "" GOTO PromptForParentPath
SET "InstallFolder=%InstallFolder:/=\%"
IF "%InstallFolder:~-1%" == "\" SET "InstallFolder=%InstallFolder:~0,-1%"
IF "%InstallFolder%" == "" GOTO PromptForParentPath
ECHO/

echo Folder "%ComfyUIFolder%"

if not exist "%ComfyUIFolder%\custom_nodes\*" (
    ECHO Invalid Path.
    ECHO There is no folder "%ComfyUIFolder%".
    ECHO/
    CHOICE /C YN /M "Do you want to enter the path once again "
    IF %ERRORLEVEL% == 2 GOTO QueryForInstallationType
    GOTO PromptForParentPath
)


:PromptForExisting
ECHO/
ECHO Please type the ComfyUI base path and press ENTER.
ECHO Or alternatively drag ^& drop the folder from Windows
ECHO Explorer on this console window and press ENTER.
ECHO/

SET "ComfyUIFolder=""
SET /P "ComfyUIFolder=Path: "
SET "ComfyUIFolder=%ComfyUIFolder:"=%"
IF "%ComfyUIFolder%" == "" GOTO PromptForExisting
SET "ComfyUIFolder=%ComfyUIFolder:/=\%"
IF "%ComfyUIFolder:~-1%" == "\" SET "ComfyUIFolder=%ComfyUIFolder:~0,-1%"
IF "%ComfyUIFolder%" == "" GOTO PromptForExisting
ECHO/

echo Folder "%ComfyUIFolder%"

if not exist "%ComfyUIFolder%\custom_nodes\*" (
    ECHO Invalid Path.
    ECHO There is no folder "%ComfyUIFolder%\custom_nodes".
    ECHO/
    CHOICE /C YN /M "Do you want to enter the path once again "
    IF %ERRORLEVEL% == 2 GOTO QueryForInstallationType
    GOTO PromptForExisting
)


:: Done 
:End
ENDLOCAL
