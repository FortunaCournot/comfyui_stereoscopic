@echo on
cd %~dp0

cd AI-Toolkit\
set ROOT="%CD%"
set PATH=%ROOT%\python_embeded\;%ROOT%\python_embeded\Scripts\;%PATH%
call ".\Start-AI-Toolkit.bat"
cd %ROOT%
