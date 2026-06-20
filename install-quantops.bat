@echo off
setlocal enabledelayedexpansion
title ComfyUI QuantOps and comfy-kitchen Installation

echo Changing directory to ComfyUI...
cd ComfyUI
if %errorlevel% neq 0 (
  echo ERROR: Failed to change directory to ComfyUI.
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

echo Checking if Triton for Windows is installed...
python -c "import triton" >nul 2>&1
if %errorlevel% neq 0 (
  echo Triton is not installed. Installing triton-windows...
  pip install -U "triton-windows<3.8"
  if %errorlevel% neq 0 (
    echo ERROR: Failed to install Triton for Windows.
    pause
    exit /b
  )
) else (
  echo Triton is already installed.
)

echo Changing directory to custom_nodes...
cd custom_nodes
if %errorlevel% neq 0 (
  echo ERROR: Failed to change directory to custom_nodes.
  pause
  exit /b
)

echo Cloning or updating ComfyUI-QuantOps...
if not exist ComfyUI-QuantOps (
  git clone https://github.com/silveroxides/ComfyUI-QuantOps
  if %errorlevel% neq 0 (
    echo ERROR: Failed to clone ComfyUI-QuantOps repository.
    pause
    exit /b
  )
) else (
  echo ComfyUI-QuantOps folder already exists. Checking for updates...
  cd ComfyUI-QuantOps
  git pull
  if %errorlevel% neq 0 (
    echo WARNING: Failed to update ComfyUI-QuantOps via git pull. Proceeding anyway.
  )
  cd ..
)

echo Changing directory to ComfyUI-QuantOps...
cd ComfyUI-QuantOps
if %errorlevel% neq 0 (
  echo ERROR: Failed to enter ComfyUI-QuantOps directory.
  pause
  exit /b
)

if exist requirements.txt (
  echo Installing requirements for ComfyUI-QuantOps...
  pip install -r requirements.txt
  if %errorlevel% neq 0 (
    echo ERROR: Failed to install ComfyUI-QuantOps requirements.
    pause
    exit /b
  )
) else (
  echo WARNING: requirements.txt not found in ComfyUI-QuantOps.
)

echo Downloading custom comfy-kitchen wheel...
powershell -Command "Invoke-WebRequest -Uri 'https://huggingface.co/silveroxides/comfy-kitchen-int8-wheels/resolve/main/comfy-kitchen-0.2.10-convrot/comfy_kitchen-0.2.10-cp312-abi3-win_amd64.whl' -OutFile 'comfy_kitchen-0.2.10-cp312-abi3-win_amd64.whl'"
if %errorlevel% neq 0 (
  echo ERROR: Failed to download comfy-kitchen wheel.
  pause
  exit /b
)

echo Installing comfy-kitchen wheel with custom flags...
pip install "%cd%\comfy_kitchen-0.2.10-cp312-abi3-win_amd64.whl" --force-reinstall --no-deps --no-cache-dir
if %errorlevel% neq 0 (
  echo ERROR: Failed to install comfy-kitchen wheel.
  if exist "comfy_kitchen-0.2.10-cp312-abi3-win_amd64.whl" del /q "comfy_kitchen-0.2.10-cp312-abi3-win_amd64.whl"
  pause
  exit /b
)

if exist "comfy_kitchen-0.2.10-cp312-abi3-win_amd64.whl" del /q "comfy_kitchen-0.2.10-cp312-abi3-win_amd64.whl"

echo.
echo Installation of QuantOps and custom comfy-kitchen wheel successful!
echo.

pause
exit /b
