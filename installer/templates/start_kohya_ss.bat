@echo on
cd %~dp0

cd kohya_ss\
set ROOT="%CD%"
set PATH=%ROOT%\python_embeded\;%ROOT%\python_embeded\Scripts\;%PATH%
call ".\gui.bat" --headless
cd %ROOT%
