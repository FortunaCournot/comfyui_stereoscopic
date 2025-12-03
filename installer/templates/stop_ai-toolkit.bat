@Echo off
cd /D %~dp0

@powershell -Command "try { Get-Process -Name node | Stop-Process; exit 0 } catch { exit 1 }" >nul 2>&1
@powershell -Command "try { Get-Process -Name python | Stop-Process; exit 0 } catch { exit 1 }" >nul 2>&1
