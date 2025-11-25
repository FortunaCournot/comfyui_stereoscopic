@echo on
cd /D %~dp0
set ROOT=%CD%

copy ComfyUI_windows_portable\ComfyUI\custom_nodes\comfyui_stereoscopic\installer\templates\*.bat .\

call ".\install_kohya_ss.bat"
del ".\install_kohya_ss.bat"

cd %ROOT%
