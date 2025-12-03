@echo on
cd /D %~dp0
set ROOT=%CD%

copy ComfyUI_windows_portable\ComfyUI\custom_nodes\comfyui_stereoscopic\installer\templates\*.bat .\

CALL .\install_ai-toolkit.bat

cd %ROOT%
del .\install_ai-toolkit.bat

