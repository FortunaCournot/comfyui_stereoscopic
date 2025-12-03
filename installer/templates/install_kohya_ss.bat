:: kohya_ss.git 
:: 
:: This file is to be executed in the folder where to install kohaya_ss.
::
:: MIT-Licensed. (c)2025 Fortuna Cournot
::
@echo on
cd /D %~dp0
set ROOT=%CD%

:: kohaya_ss retieve
git clone --recursive https://github.com/bmaltais/kohya_ss.git 
cd kohya_ss\

:: INSTALL PYTHON 3.12 embedded and pip inside
curl.exe -OL https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip --ssl-no-revoke --retry 200 --retry-all-errors
md python_embeded
cd python_embeded
tar.exe -xf ..\python-3.12.10-embed-amd64.zip
erase ..\python-3.12.10-embed-amd64.zip
curl.exe -sSL https://bootstrap.pypa.io/get-pip.py -o get-pip.py --ssl-no-revoke --retry 200 --retry-all-errors
Echo %ROOT%> python312._pth
Echo Lib/site-packages> python312._pth
Echo Lib>> python312._pth
Echo Scripts>> python312._pth
Echo python312.zip>> python312._pth
Echo %CD%>> python312._pth
Echo # import site>> python312._pth
.\python.exe -I get-pip.py %PIPargs%
.\python.exe -I -m pip install --upgrade pip
.\python.exe -m pip install --target . setuptools
.\python.exe -m pip install --target . tkinter-embed
set PATH=%CD%\;%CD%\Scripts\;%PATH%
cd ..
python -V

:: Install torch, triton
python -m pip install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu128
python -m pip install poetry-core
python -m pip install triton-windows==3.4.0.post20
python -m pip install --upgrade triton-windows
python -m pip install hf_xet

:: installation of venv
python -m pip install virtualenv
python -m virtualenv venv
call .\venv\Scripts\activate
pip install easygui

:: Complete installation of kohaya_ss
call ".\setup.bat" --headless

call .\venv\Scripts\deactivate
cd %ROOT%
