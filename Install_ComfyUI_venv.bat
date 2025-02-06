@echo off
title ComfyUI Virtual Environment Installation

echo Checking for Git...

where git >nul 2>&1
if %errorlevel% neq 0 (
  echo Git is not installed.
  echo.
  echo Please download and install Git from:
  echo https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/Git-2.47.1.2-64-bit.exe
  echo.
  echo After installation, please run this script again.
  pause
  exit /b
)

echo Git found.

echo Cloning ComfyUI...
git clone https://github.com/comfyanonymous/ComfyUI

echo Changing directory to ComfyUI...
cd ComfyUI

echo Creating virtual environment...
python -m venv venv

echo Activating virtual environment...
call venv\Scripts\activate

echo Checking for NVIDIA GPU Drivers...

sc query "NVDisplay.ContainerLocalSystem" >nul 2>&1
if %errorlevel% neq 0 (
    echo NVIDIA Display Container Local System Service not found. Drivers may not be installed.
) else (
    echo NVIDIA Display Container Local System Service found. Drivers are likely installed.
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124
    echo installing pytorch for CUDA
)



echo Installing requirements...
pip install -r requirements.txt

echo Changing directory to custom_nodes...
cd custom_nodes

echo Cloning ComfyUI-Manager...
git clone https://github.com/ltdrdata/ComfyUI-Manager

echo Changing directory to ComfyUI-Manager...
cd ComfyUI-Manager

echo Installing ComfyUI-Manager requirements...
pip install -r requirements.txt

echo Going up two directories...
cd ../..

echo Downloading comfyui-start.bat...
powershell -Command "Invoke-WebRequest -Uri 'https://github.com/silveroxides/ComfyUI-StartScripts/raw/refs/heads/main/comfyui-start.bat' -OutFile 'comfyui-start.bat'"

echo Downloading comfyui.bat...
powershell -Command "Invoke-WebRequest -Uri 'https://github.com/silveroxides/ComfyUI-StartScripts/raw/refs/heads/main/comfyui.bat' -OutFile 'comfyui.bat'"

echo.
echo Installation successful.
echo To run ComfyUI, double click the comfyui-start.bat file.
echo.

pause
exit /b