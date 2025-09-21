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
if [%1]==[] goto DoChecks
SET INSTALLATIONTYPE=1
SET InstallFolder=%1
echo Installfolder: %InstallFolder%
SET INTERACTIVE=0
SET VRWEAREPATH=

:DoChecks
IF %INTERACTIVE% equ 0 GOTO CheckOS
CLS
ECHO/
ECHO === VR we are - Installation ===
ECHO/
::pass

:: CheckOS
:CheckOS
FOR /f "tokens=4-5 delims=. " %%i IN ('ver') DO SET VERSION=%%i.%%j
IF "%version%" == "6.3" ECHO Windows 8.1 not supported.
IF "%version%" == "6.2" ECHO Windows 8 not supported.
IF "%version%" == "6.1" ECHO Windows 7 not supported.
IF "%version%" == "6.0" ECHO Windows Vista not supported.
IF "%version%" == "10.0" GOTO CheckArch
ECHO OS version %version%
GOTO Fail

:CheckArch
reg Query "HKLM\Hardware\Description\System\CentralProcessor\0" | find /i "x86" > NUL && set OS=32BIT || set OS=64BIT
if %OS%==32BIT echo [91mThis is a 32bit operating system. Not supported.[0m
if %OS%==64BIT GOTO QueryForInstallationType
echo OS Architecture %OS%
GOTO Fail


:QueryForInstallationType
:: Check for existing software in registry ...
:: ---

:: Read the Git for Windows installation path from the Registry.
::echo Checking for existing Git installation...
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
ECHO [91mGit not found. Please install from [96m https://git-scm.com/ [0m
GOTO Fail
:GIT_END_REG_SEARCH

:CHECK_GIT_PATH
:: Make sure Bash is in PATH (for running scripts).
SET PATH=%GITPATH%bin;%PATH%
git --version >"%temp%"\version.txt 2> nul
IF %ERRORLEVEL% == 0 GOTO CHECK_GIT_VERSION
ECHO * [91mGit to old (version is below 2.37), you need to update before installing VR we are.[0m
ECHO   [91mPlease download Git from [96m https://git-scm.com/ [0m
Goto Fail

:CHECK_GIT_VERSION
set /p Version=<"%temp%"\version.txt
del "%temp%"\version.txt
echo * %Version%  - [94mRecommended: 2.51[0m
::pass


:CHECK_FFMPEG_PATH
ffmpeg -version >"%temp%"\version.txt 2> nul
IF %ERRORLEVEL% == 0 GOTO CHECK_FFMPEG_VERSION
echo * [91mffmpeg not found in path, please install from [96m https://www.ffmpeg.org/ [0m
echo   [91mand add path to environment variable Path.[0m
echo   [91mE.g. call as admin: [96m"C:\Windows\system32\rundll32.exe" sysdm.cpl,EditEnvironmentVariables[0m
GOTO Fail

:CHECK_FFMPEG_VERSION
set /p Version=<"%temp%"\version.txt
del "%temp%"\version.txt
echo * %Version%  - [94mRecommended: 8.0[0m
::pass

:CHECK_EXIF_PATH
exiftool -ver >"%temp%"\version.txt 2> nul
IF %ERRORLEVEL% == 0 GOTO CHECK_EXIF_VERSION
echo * [91mexiftool not found in path, please install from [96m https://exiftool.org/ [0m
echo   [91mrename binary to exiftool.exe, and add path to environment variable Path.[0m
echo   [91mE.g. call as admin: [96m"C:\Windows\system32\rundll32.exe" sysdm.cpl,EditEnvironmentVariables[0m
GOTO Fail

:CHECK_EXIF_VERSION
set /p Version=<"%temp%"\version.txt
del "%temp%"\version.txt
echo * Exiftool %Version% - [94mRecommended: 13.33[0m
::pass

:CHECK_VRWEARE_VERSION
:: Read the VR we are installation path from the Registry.
:: echo Checking for existing VR we are installation...
for %%k in (HKCU HKLM) do (
    for %%w in (\ \Wow6432Node\) do (
        for /f "skip=2 delims=: tokens=1*" %%a in ('reg query "%%k\SOFTWARE%%wMicrosoft\Windows\CurrentVersion\Uninstall\VRweare" /v InstallLocation 2^> nul') do (
            for /f "tokens=3" %%z in ("%%a") do (
                set VRWEAREPATH=%%z:%%b
                goto VRWEARE_FOUND_REG_ENTRY
            )
        )
    )

)
:: VR we are not installed
IF %INTERACTIVE% equ 1 SET InstallFolder=
set VRWEAREPATH=
GOTO VRWEARE_END_REG_SEARCH

:: Found reg entry
:VRWEARE_FOUND_REG_ENTRY
IF %INTERACTIVE% equ 1 SET InstallFolder="%VRWEAREPATH%"\..
IF %INTERACTIVE% equ 1 echo * Found existing installation of VR we are at [2m%InstallFolder%[0m
IF %INTERACTIVE% equ 0 echo Found VR we are reg entry at "%VRWEAREPATH%"
IF %INTERACTIVE% equ 0 echo Removing existing VR we are installation from registry
IF %INTERACTIVE% equ 0 CALL "%VRWEAREPATH%"\Uninstall.cmd
IF %INTERACTIVE% equ 0 GOTO VRWEARE_END_REG_SEARCH
:: Interactive: Ask user for new Installation
ECHO/
ECHO Please choose the installation type:
ECHO/ 
ECHO   1 - Keep existing installation and stop.
ECHO   2 - Create new installation under different path and update registry.
ECHO   Q - Quit
ECHO/
CHOICE /C 12Q /M ""
IF ERRORLEVEL 3 GOTO End
IF ERRORLEVEL 2 GOTO QueryForInstallationType
GOTO End




::continue...
:VRWEARE_END_REG_SEARCH
IF not exist "%VRWEAREPATH%\*" (
  IF %INTERACTIVE% equ 1 SET InstallFolder=
  set VRWEAREPATH=
)


:: Welcome Screen 
:QueryForInstallationType
::CLS
IF %INTERACTIVE% equ 0 GOTO VRWEARE_PARENT_CHECK
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


:: Interactive Installation Path handling
:VRWEARE_PARENT_QUERY
if not "%VRWEAREPATH%"=="" if exist "%VRWEAREPATH%\*" (
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
echo InstallFolder: %InstallFolder%
IF "%InstallFolder%"=="" (
	echo Error: Installfolder invalid: '%InstallFolder%'
	echo It must be an existing folder.
	GOTO Fail
)
IF not exist "%InstallFolder%\*" (
	echo Error: Installfolder not found: '%InstallFolder%'
	echo It must be an existing folder.
	GOTO Fail
)
echo VRWEAREPATH: %VRWEAREPATH%
IF not exist "%VRWEAREPATH%\*" (
	mkdir "%InstallFolder%"\vrweare
)
IF not exist "%InstallFolder%\vrweare\*" (
	ECHO ERROR: Invalid Install Path. Can't create folder "%InstallFolder%\vrweare".
	ECHO/
	IF %INTERACTIVE% equ 1 GOTO VRWEARE_PARENT_QUERY
	GOTO Fail
)
CD /D "%InstallFolder%"\vrweare
SET "VRWEAREPATH=%cd%"
ECHO VRWEAREPATH: %VRWEAREPATH%
GOTO REGISTER

::REGISTER
:REGISTER
echo reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\VRweare" /f >"%VRWEAREPATH%\\Uninstall.cmd"
echo Updating registry...
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\VRweare" /v DisplayName /t REG_SZ /f /d "VR we are"
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\VRweare" /v DisplayVersion /t REG_SZ /f /d %VRWEARE_VERSION%
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\VRweare" /v Publisher /t REG_SZ /f /d "Fortuna Cournot"
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\VRweare" /v InstallLocation /t REG_SZ /f /d "%VRWEAREPATH%"
::reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\VRweare" /v NoModify /t REG_DWORD /f /d 1
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\VRweare" /v InstallLocation /t REG_SZ /f /d "%VRWEAREPATH%"
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\VRweare" /v UninstallString /t REG_SZ /f /d "%VRWEAREPATH%\\Uninstall.cmd"

:: VR we are Path registered.
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
