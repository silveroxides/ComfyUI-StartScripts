@echo off
setlocal enabledelayedexpansion
title ComfyUI Virtual Environment Installation

echo Checking for Git...
where git >nul 2>&1
if %errorlevel% neq 0 (
  echo Git is not installed or not found in PATH.
  echo.
  echo Please download and install Git from:
  echo https://github.com/git-for-windows/git/releases/download/v2.52.0.windows.1/Git-2.52.0-64-bit.exe
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
  echo Please download and install Python 3.13.13 or higher from:
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
set REQ_MINOR=13
set REQ_PATCH=13

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
nvidia-smi >nul 2>&1
if %errorlevel% neq 0 (
    echo WARNING: nvidia-smi not found. NVIDIA drivers may not be installed.
    echo.
    echo Please download and install NVIDIA drivers from:
    echo https://www.nvidia.com/en-us/geforce/drivers/
    echo.
    echo After installation, please run this script again.
    pause
    exit /b
)

echo NVIDIA drivers found. Checking driver version...
for /f "tokens=*" %%i in ('nvidia-smi --query-gpu=driver_version --format=csv,noheader 2^>nul') do set "DRIVER_VERSION=%%i"

rem Extract major version number (before the first dot)
for /f "tokens=1 delims=." %%a in ("!DRIVER_VERSION!") do set "DRIVER_MAJOR=%%a"

echo Found NVIDIA driver version: !DRIVER_VERSION!
echo Required minimum driver version: 580.x
echo.

if !DRIVER_MAJOR! LSS 580 (
    echo WARNING: Your NVIDIA driver version ^(!DRIVER_VERSION!^) is below the required minimum ^(580^).
    echo.
    echo CUDA 13.0 requires NVIDIA driver version 580 or higher.
    echo.
    echo Please download and install the latest NVIDIA drivers from:
    echo https://www.nvidia.com/en-us/geforce/drivers/
    echo.
    echo After updating your drivers, please run this script again.
    pause
    exit /b
)

echo NVIDIA driver version check passed.
echo.

echo Installing PyTorch for CUDA 13.0...
pip install torch==2.12.0 torchvision==0.27.0 torchaudio==2.12.0 --index-url https://download.pytorch.org/whl/cu130
if %errorlevel% neq 0 (
    echo WARNING: Failed to install PyTorch with CUDA 13.0 support. Installation will continue, but GPU acceleration might not work.
    pause
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
