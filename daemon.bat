@echo off

WHERE git.exe >%temp%\.tmpstereoscopic
SET /p GITBIN= < %temp%\.tmpstereoscopic
DEL %temp%\.tmpstereoscopic

echo %GITBIN%

for /F "delims=" %%i in ("%GITBIN%") do set dirname="%%~dpi" 
set dirname=%dirname:~0,-1%

echo "Starting daemon in git bash shell..."
echo on
%dirname%..\git-bash.exe daemon.sh
 




