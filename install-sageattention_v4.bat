@echo off
setlocal enabledelayedexpansion
title ComfyUI SageAttention and Flash Attention Installation

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

echo Installing Triton for Windows...
pip install -U "triton-windows<3.8"
if %errorlevel% neq 0 (
  echo ERROR: Failed to install Triton for Windows.
  pause
  exit /b
)


echo Downloading SageAttention wheel...
powershell -Command "Invoke-WebRequest -Uri 'https://github.com/woct0rdho/SageAttention/releases/download/v2.2.0-windows.post5/sageattention-2.2.0+cu130torch2.10.0andhigher.post5-cp310-abi3-win_amd64.whl' -OutFile 'sageattention-2.2.0+cu130torch2.10.0andhigher.post5-cp310-abi3-win_amd64.whl'"
if %errorlevel% neq 0 (
  echo WARNING: Failed to download SageAttention wheel.
)

echo Installing SageAttention wheel for Windows...
pip install "%cd%\sageattention-2.2.0+cu130torch2.10.0andhigher.post5-cp310-abi3-win_amd64.whl"
if %errorlevel% neq 0 (
  echo ERROR: Failed to install SageAttention for Windows.
  if exist "sageattention-2.2.0+cu130torch2.10.0andhigher.post5-cp310-abi3-win_amd64.whl" del /q "sageattention-2.2.0+cu130torch2.10.0andhigher.post5-cp310-abi3-win_amd64.whl"
  pause
  exit /b
)
if exist "sageattention-2.2.0+cu130torch2.10.0andhigher.post5-cp310-abi3-win_amd64.whl" del /q "sageattention-2.2.0+cu130torch2.10.0andhigher.post5-cp310-abi3-win_amd64.whl"


echo Downloading Flash Attention wheel...
powershell -Command "Invoke-WebRequest -Uri 'https://huggingface.co/Wildminder/AI-windows-whl/resolve/main/flash_attn-2.8.4+d20260328cu130torch2.12.0cxx11abiTRUE-cp313-cp313-win_amd64.whl' -OutFile 'flash_attn-2.8.4+d20260328cu130torch2.12.0cxx11abiTRUE-cp313-cp313-win_amd64.whl'"
if %errorlevel% neq 0 (
  echo WARNING: Failed to download Flash Attention wheel.
)

echo Installing Flash Attention wheel for Windows...
pip install "%cd%\flash_attn-2.8.4+d20260328cu130torch2.12.0cxx11abiTRUE-cp313-cp313-win_amd64.whl"
if %errorlevel% neq 0 (
  echo ERROR: Failed to install Flash Attention for Windows.
  if exist "flash_attn-2.8.4+d20260328cu130torch2.12.0cxx11abiTRUE-cp313-cp313-win_amd64.whl" del /q "flash_attn-2.8.4+d20260328cu130torch2.12.0cxx11abiTRUE-cp313-cp313-win_amd64.whl"
  pause
  exit /b
)
if exist "flash_attn-2.8.4+d20260328cu130torch2.12.0cxx11abiTRUE-cp313-cp313-win_amd64.whl" del /q "flash_attn-2.8.4+d20260328cu130torch2.12.0cxx11abiTRUE-cp313-cp313-win_amd64.whl"


echo.
echo Unified attention acceleration installation successful (check warnings above).
echo both SageAttention and Flash Attention have been successfully installed!
echo.

pause
exit /b
