@echo off
setlocal enabledelayedexpansion
title ComfyUI SageAttention Installation

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
pip install triton-windows==3.5.1.post24
if %errorlevel% neq 0 (
  echo ERROR: Failed to install Triton for Windows.
  pause
  exit /b
)


echo Downloading SageAttention wheel...
powershell -Command "Invoke-WebRequest -Uri 'https://github.com/woct0rdho/SageAttention/releases/download/v2.2.0-windows.post4/sageattention-2.2.0+cu130torch2.9.0andhigher.post4-cp39-abi3-win_amd64.whl' -OutFile 'sageattention-2.2.0+cu130torch2.9.0andhigher.post4-cp39-abi3-win_amd64.whl'"
if %errorlevel% neq 0 (
  echo WARNING: Failed to download SageAttention wheel.
)

echo Installing SageAttention wheel for Windows...
pip install "%cd%\sageattention-2.2.0+cu130torch2.9.0andhigher.post4-cp39-abi3-win_amd64.whl"
if %errorlevel% neq 0 (
  echo ERROR: Failed to install SageAttention for Windows.
  pause
  exit /b
)

echo.
echo Installation successful (check warnings above).
echo.

pause
exit /b