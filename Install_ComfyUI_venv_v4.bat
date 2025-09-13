@echo off
setlocal enabledelayedexpansion
title ComfyUI Virtual Environment Installation

echo Checking for Git...
where git >nul 2>&1
if %errorlevel% neq 0 (
  echo Git is not installed or not found in PATH.
  echo.
  echo Please download and install Git from:
  echo https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/Git-2.47.1.2-64-bit.exe
  echo Make sure Git is added to your PATH during installation.
  echo.
  echo After installation, please run this script again.
  pause
  exit /b
)
echo Git found.
echo.

echo Checking for Python in PATH...
where python >nul 2>&1
if %errorlevel% neq 0 (
  echo Python is not installed or not found in PATH.
  echo.
  echo Please download and install Python 3.12.7 or higher from:
  echo https://www.python.org/downloads/
  echo.
  echo IMPORTANT: During installation, ensure you check the box "Add python.exe to PATH".
  echo.
  echo After installation, please close this window and run the script again.
  pause
  exit /b
)
echo Python found in PATH.
echo.

echo Checking Python version...
set REQ_MAJOR=3
set REQ_MINOR=12
set REQ_PATCH=7

rem Capture Python version string
for /f "tokens=*" %%v in ('python --version 2^>^&1') do set "PYTHON_VERSION_STR=%%v"

rem Extract version numbers
set "PYTHON_VERSION_NUM=!PYTHON_VERSION_STR:Python =!"
for /f "tokens=1,2,3 delims=." %%a in ("!PYTHON_VERSION_NUM!") do (
    set "PY_MAJOR=%%a"
    set "PY_MINOR=%%b"
    set "PY_PATCH=%%c"
)

rem Basic check if we got numbers
if not defined PY_MAJOR (
    echo ERROR: Could not determine Python version from output: "!PYTHON_VERSION_STR!"
    echo Please ensure 'python --version' works correctly.
    pause
    exit /b
)
if not defined PY_MINOR set "PY_MINOR=0"
if not defined PY_PATCH set "PY_PATCH=0"

echo Found Python version: !PY_MAJOR!.!PY_MINOR!.!PY_PATCH!
echo Required version: %REQ_MAJOR%.%REQ_MINOR%.%REQ_PATCH% or higher.
echo.

set VERSION_OK=0
if !PY_MAJOR! LSS %REQ_MAJOR% goto :version_check_failed_python
if !PY_MAJOR! GTR %REQ_MAJOR% set VERSION_OK=1
if !PY_MAJOR! EQU %REQ_MAJOR% (
    if !PY_MINOR! LSS %REQ_MINOR% goto :version_check_failed_python
    if !PY_MINOR! GTR %REQ_MINOR% set VERSION_OK=1
    if !PY_MINOR! EQU %REQ_MINOR% (
        if !PY_PATCH! LSS %REQ_PATCH% goto :version_check_failed_python
        if !PY_PATCH! GEQ %REQ_PATCH% set VERSION_OK=1
    )
)

if !VERSION_OK! EQU 0 goto :version_check_failed_python

echo Python version check passed.
echo.
goto :continue_install

:version_check_failed_python
echo ERROR: Your Python version (!PY_MAJOR!.!PY_MINOR!.!PY_PATCH!) is lower than the required version (%REQ_MAJOR%.%REQ_MINOR%.%REQ_PATCH%).
echo.
echo Please upgrade Python by downloading the latest version from:
echo https://www.python.org/downloads/
echo.
echo Make sure to uninstall older versions if necessary and ensure the new version is added to your PATH.
echo After upgrading, please close this window and run the script again.
pause
exit /b

:continue_install
echo Cloning ComfyUI...
git clone https://github.com/comfyanonymous/ComfyUI
if %errorlevel% neq 0 (
  echo ERROR: Failed to clone ComfyUI.
  pause
  exit /b
)

echo Changing directory to ComfyUI...
cd ComfyUI
if %errorlevel% neq 0 (
  echo ERROR: Failed to change directory to ComfyUI.
  pause
  exit /b
)

echo Fetching latest changes and specific Pull Request...
git fetch
if %errorlevel% neq 0 (
  echo ERROR: git fetch failed.
  pause
  exit /b
)
git pull
if %errorlevel% neq 0 (
  echo ERROR: git pull failed.
  pause
  exit /b
)
echo.


echo Creating virtual environment...
python -m venv venv
if %errorlevel% neq 0 (
  echo ERROR: Failed to create virtual environment.
  pause
  exit /b
)


echo Activating virtual environment...
call venv\Scripts\activate
if %errorlevel% neq 0 (
  echo ERROR: Failed to activate virtual environment.
  pause
  exit /b
)


echo Checking for NVIDIA GPU Drivers...
sc query "NVDisplay.ContainerLocalSystem" >nul 2>&1
if %errorlevel% neq 0 (
    echo NVIDIA Display Container Local System Service not found. Drivers may not be installed.
    rem Consider adding CPU PyTorch install here if desired, otherwise it will likely fail below
) else (
    echo NVIDIA Display Container Local System Service found. Drivers are likely installed.
    echo Installing PyTorch for CUDA 12.8...
    pip install torch==2.8.0 torchvision==0.23.0 torchaudio==2.8.0 --index-url https://download.pytorch.org/whl/cu128
    if %errorlevel% neq 0 (
      echo WARNING: Failed to install PyTorch with CUDA 12.8 support. Installation will continue, but GPU acceleration might not work.
      pause
    )
)


echo Installing requirements...
pip install -r requirements.txt
if %errorlevel% neq 0 (
  echo ERROR: Failed to install requirements from requirements.txt.
  pause
  exit /b
)

echo Changing directory to custom_nodes...
cd custom_nodes
if %errorlevel% neq 0 (
  echo ERROR: Failed to change directory to custom_nodes.
  pause
  exit /b
)

echo Cloning ComfyUI-Manager...
git clone https://github.com/ltdrdata/ComfyUI-Manager
if %errorlevel% neq 0 (
  echo WARNING: Failed to clone ComfyUI-Manager. You may need to install it manually later.
) else (
  echo Changing directory to ComfyUI-Manager...
  cd ComfyUI-Manager
  if %errorlevel% neq 0 (
     echo WARNING: Failed to change directory into ComfyUI-Manager. Cannot install its requirements.
  ) else (
     if exist requirements.txt (
        echo Installing ComfyUI-Manager requirements...
        pip install -r requirements.txt
        if %errorlevel% neq 0 (
           echo WARNING: Failed to install ComfyUI-Manager requirements.
        )
     ) else (
        echo No requirements.txt found for ComfyUI-Manager. Skipping.
     )
     cd ..
  )
)


echo Going up one directory (back to ComfyUI root)...
cd ..
if %errorlevel% neq 0 (
  echo ERROR: Failed to navigate back to the main ComfyUI directory.
  pause
  exit /b
)

echo Downloading comfyui-start.bat...
powershell -Command "Invoke-WebRequest -Uri 'https://github.com/silveroxides/ComfyUI-StartScripts/releases/download/v1.0a/comfyui-start.bat' -OutFile 'comfyui-start.bat'"
if %errorlevel% neq 0 (
  echo WARNING: Failed to download comfyui-start.bat.
)

echo Downloading comfyui.bat...
powershell -Command "Invoke-WebRequest -Uri 'https://github.com/silveroxides/ComfyUI-StartScripts/releases/download/v1.0a/comfyui.bat' -OutFile 'comfyui.bat'"
if %errorlevel% neq 0 (
  echo WARNING: Failed to download comfyui.bat.
)

echo.
echo Installation successful (check warnings above).
echo To run ComfyUI, double click the comfyui-start.bat file inside the ComfyUI directory.
echo.

pause
exit /b
