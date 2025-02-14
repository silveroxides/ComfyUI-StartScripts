rem @echo off

rem Path to the folder containing your python.exe ececutable if it is not already in the Path environment variable.
rem set PYTHON=
rem Path to the folder containing your git.exe executable if it is not already in the Path environment variable.
rem set GIT_PATH=
rem Set this to the path of any existing ComfyUI venv if you prefer to use that
set VENV_DIR=
set COMMANDLINE_ARGS=--windows-standalone

call comfyui.bat
