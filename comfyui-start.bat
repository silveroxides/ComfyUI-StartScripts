@echo off
rem Optional overrides: use an unquoted path as the value inside set "NAME=value".
rem set "PYTHON=C:\path\to\python.exe"
rem set "GIT_PATH=C:\path\to\Git\cmd"
rem set "VENV_DIR=C:\path\to\existing\.venv"
rem VENV_DIR defaults to .venv beside this script. VENV_DIR=- or SKIP_VENV=1 skips it.
if not defined COMMANDLINE_ARGS set "COMMANDLINE_ARGS=--windows-standalone"
call "%~dp0comfyui.bat" %*
exit /b %errorlevel%
