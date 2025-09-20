::====================================================================
:: VR we are - (C)2025 Fortuna Cournot, https://www.3d-gallery.org/
:: Windows Installer
::====================================================================
@ECHO OFF 
:: Windows version check 
IF NOT "%OS%"=="Windows_NT" GOTO Fail
:: Keep variable local 
SETLOCAL enabledelayedexpansion

SET VRWEARE_VERSION=4.0

SET INTERACTIVE=1
if [%1]==[] goto CheckOS
SET INSTALLATIONTYPE=1
SET InstallFolder=%1
SET INTERACTIVE=0
SET VRWEAREPATH=

:: CheckOS
:CheckOS
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
if %OS%==64BIT GOTO QueryForInstallationType
echo OS Architecture %OS%
GOTO Fail


:QueryForInstallationType
:: Check for existing software in registry ...
:: ---
:: Read the VR we are installation path from the Registry.
for %%k in (HKCU HKLM) do (
    for %%w in (\ \Wow6432Node\) do (
        for /f "skip=2 delims=: tokens=1*" %%a in ('reg query "%%k\SOFTWARE%%wMicrosoft\Windows\CurrentVersion\Uninstall\VRweare" /v InstallLocation 2^> nul') do (
            for /f "tokens=3" %%z in ("%%a") do (
                set VRWEAREPATH=%%z:%%b
                ::echo Found VR we are reg entry at "!VRWEAREPATH!".
                goto VRWEARE_END_REG_SEARCH
            )
        )
    )
)
:VRWEARE_END_REG_SEARCH
:: Read the Git for Windows installation path from the Registry.
for %%k in (HKCU HKLM) do (
    for %%w in (\ \Wow6432Node\) do (
        for /f "skip=2 delims=: tokens=1*" %%a in ('reg query "%%k\SOFTWARE%%wMicrosoft\Windows\CurrentVersion\Uninstall\Git_is1" /v InstallLocation 2^> nul') do (
            for /f "tokens=3" %%z in ("%%a") do (
                set GITPATH=%%z:%%b
                ::echo Found Git reg entry at "!GITPATH!".
                goto GIT_END_REG_SEARCH
            )
        )
    )
)
:GIT_END_REG_SEARCH

:: Welcome Screen 
:QueryForInstallationType
::CLS
IF %INTERACTIVE% equ 0 GOTO VRWEARE_PARENT_CHECK
ECHO/
ECHO === VR we are - Installation ===
ECHO/
ECHO Please choose the installation type:
ECHO/ 
ECHO   1 - For automatic download and installation of all components.
ECHO   2 - For a guidance of a manual installation.
ECHO   Q - Quit
ECHO/
CHOICE /C 12Q /M ""
SET INSTALLATIONTYPE=0
IF ERRORLEVEL 1 SET INSTALLATIONTYPE=1
IF ERRORLEVEL 2 SET INSTALLATIONTYPE=2
IF ERRORLEVEL 3 GOTO End


:: Interactive INstallation Path handling
:VRWEARE_PARENT_QUERY
if not "%VRWEAREPATH%"=="" if exist "%VRWEAREPATH%\*" (
	SET InstallFolder="VRWEAREPATH%"
	echo hmm %InstallFolder%
)

ECHO/
ECHO Please type the parent path of the installation and press ENTER.
ECHO/
ECHO Or alternatively drag ^& drop the folder from Windows
ECHO Explorer on this console window and press ENTER.
ECHO/

SET InstallFolder=""
SET /P "InstallFolder=Path: "
SET "InstallFolder=%InstallFolder:"=%"
IF "%InstallFolder%" == "" GOTO VRWEARE_PARENT_QUERY
SET "InstallFolder=%InstallFolder:/=\%"
IF "%InstallFolder:~-1%" == "\" SET "InstallFolder=%InstallFolder:~0,-1%"
IF "%InstallFolder%" == "" GOTO VRWEARE_PARENT_QUERY
ECHO/


if not exist "%InstallFolder%\*" (
	ECHO Invalid Path. There is no folder "%InstallFolder%".
	ECHO/
	CALL
	CHOICE /C YN /M "Do you want to enter the path once again "
	IF ERRORLEVEL 2 GOTO QueryForInstallationType
	IF ERRORLEVEL 1 GOTO VRWEARE_PARENT_QUERY
	GOTO VRWEARE_PARENT_QUERY
)

:: Interactive Installation Path handling
:VRWEARE_PARENT_CHECK
IF not exist "%InstallFolder%\vrweare\*" (
	mkdir "%InstallFolder%"\vrweare
)
IF not exist "%InstallFolder%\vrweare\*" (
	ECHO ERROR: Invalid Install Path. Can't create folder "%InstallFolder%\vrweare".
	ECHO/
	IF %INTERACTIVE% equ 1 GOTO VRWEARE_PARENT_QUERY
	GOTO Fail
)
GOTO REGISTER


::REGISTER
:REGISTER
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\VRweare" /v DisplayName /t REG_SZ /f /d "VR we are"
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\VRweare" /v DisplayVersion /t REG_SZ /f /d %VRWEARE_VERSION%
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\VRweare" /v Publisher /t REG_SZ /f /d "Fortuna Cournot"
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\VRweare" /v InstallLocation /t REG_SZ /f /d "%InstallFolder%\\VRweare"
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\VRweare" /v NoModify /t REG_DWORD /f /d 1

GOTO End












:INSTALLGIT
:: Make sure Bash is in PATH (for running scripts).
SET PATH=%GITPATH%bin;%PATH%
git --version
IF %ERRORLEVEL% == 0 GOTO Start
ECHO Git version to old. Please update.
GOTO Fail
:: Do something with Git ...

:GIT_NOT_FOUND
ECHO Please install Git version 2.37 or later from https://git-scm.com/
Goto Fail





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

GOTO End

:Fail 
ECHO Installation failed. (%ERRORLEVEL%)
exit /B 1

:: Done 
:End
ENDLOCAL
exit /B 0
