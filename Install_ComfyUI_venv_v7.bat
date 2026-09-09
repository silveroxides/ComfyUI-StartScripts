@echo off
setlocal DisableDelayedExpansion
title ComfyUI v7 - Python 3.13 / CUDA 13.0

rem ---------------------------------------------------------------------------
rem Installation targets. Keep these in sync with release.toml.
rem ---------------------------------------------------------------------------
set "RELEASE_TAG=v7.0install"
set "TORCH_VERSION=2.12.1"
set "TORCHVISION_VERSION=0.27.1"
set "CUDA_VARIANT=cu130"
set "PYTHON_MIN=3.13.13"

rem Keep delayed expansion disabled: installation paths may contain ! characters.
set "INSTALLER_DIR=%~dp0"
set "EXIT_CODE=1"
set "OPTIONAL_FAILED=0"
set "TRITON_STATUS=skipped"
set "SAGE_STATUS=skipped"
set "FLASH_STATUS=skipped"
set "BLOCK_STATUS=skipped"
set "SPARGE_STATUS=skipped"
set "LAUNCHER_TEMP="
pushd "%INSTALLER_DIR%"
if errorlevel 1 exit /b 1
set "COMFY_DIR=%CD%\ComfyUI"
set "VENV_PYTHON=%COMFY_DIR%\.venv\Scripts\python.exe"

rem ---------------------------------------------------------------------------
rem 1. Check tools and select Python without modifying an existing environment.
rem ---------------------------------------------------------------------------
where git.exe >nul 2>&1
if errorlevel 1 goto :missing_git
where curl.exe >nul 2>&1
if errorlevel 1 goto :missing_curl
if exist "%COMFY_DIR%\.venv" goto :existing_python
set "BASE_PYTHON="
for /f "delims=" %%P in ('py -3.13 -c "import sys; print(sys.executable)" 2^>nul') do set "BASE_PYTHON=%%P"
if defined BASE_PYTHON goto :check_python
for /f "delims=" %%P in ('python -c "import sys; print(sys.executable)" 2^>nul') do set "BASE_PYTHON=%%P"
if not defined BASE_PYTHON goto :bad_python
goto :check_python
:existing_python
if not exist "%VENV_PYTHON%" goto :bad_python
set "BASE_PYTHON=%VENV_PYTHON%"
:check_python
echo Checking Python version and wheel compatibility...
"%BASE_PYTHON%" -c "import sys; print(sys.version); assert sys.implementation.name == 'cpython'; assert (3,13,13) <= sys.version_info[:3] < (3,14,0)"
if errorlevel 1 goto :bad_python
"%BASE_PYTHON%" -c "import platform, struct; assert struct.calcsize('P') == 8; assert platform.machine().lower() in ('amd64','x86_64')"
if errorlevel 1 goto :bad_python
"%BASE_PYTHON%" -c "import sysconfig; assert not sysconfig.get_config_var('Py_GIL_DISABLED')"
if errorlevel 1 goto :bad_python

rem ---------------------------------------------------------------------------
rem 2. Check NVIDIA drivers. No driver or CUDA Toolkit is installed by this script.
rem ---------------------------------------------------------------------------
where nvidia-smi.exe >nul 2>&1
if errorlevel 1 goto :bad_driver
nvidia-smi.exe --query-gpu=name,driver_version --format=csv,noheader
if errorlevel 1 goto :bad_driver
set "DRIVER_FOUND="
set "DRIVER_FAILED="
for /f "delims=" %%D in ('nvidia-smi.exe --query-gpu=driver_version --format=csv,noheader 2^>nul') do (
    set "DRIVER_VERSION=%%D"
    call :check_driver
)
if not defined DRIVER_FOUND goto :bad_driver
if defined DRIVER_FAILED goto :bad_driver
echo R580 is the CUDA 13.x baseline. Use a current GPU driver for JIT kernels.
echo Optional kernels have additional GPU-specific requirements.

rem ---------------------------------------------------------------------------
rem 3. Clone/update ComfyUI and create/reuse its .venv, as in v6.
rem ---------------------------------------------------------------------------
set "REPO_DIR=%COMFY_DIR%"
set "REPO_URL=https://github.com/Comfy-Org/ComfyUI.git"
set "REPO_NAME=ComfyUI"
set "LEGACY_OWNER=comfyanonymous"
call :sync_repo
if errorlevel 1 goto :failed
if exist "%VENV_PYTHON%" goto :venv_ready
"%BASE_PYTHON%" -m venv "%COMFY_DIR%\.venv"
if errorlevel 1 goto :failed
:venv_ready
"%VENV_PYTHON%" -m pip --version
if errorlevel 1 goto :failed

rem ---------------------------------------------------------------------------
rem 4. Install the requested Torch build, then normal ComfyUI requirements.
rem ---------------------------------------------------------------------------
echo Installing torch %TORCH_VERSION% and torchvision %TORCHVISION_VERSION% for %CUDA_VARIANT%...
"%VENV_PYTHON%" -m pip install torch==2.12.1 torchvision==0.27.1 --index-url https://download.pytorch.org/whl/cu130
if errorlevel 1 goto :failed
echo Installing unchanged ComfyUI requirements, including its TorchAudio requirement...
"%VENV_PYTHON%" -m pip install -r "%COMFY_DIR%\requirements.txt"
if errorlevel 1 goto :failed

rem ---------------------------------------------------------------------------
rem 5. Install/update ComfyUI-Manager as a custom node.
rem ---------------------------------------------------------------------------
set "REPO_DIR=%COMFY_DIR%\custom_nodes\ComfyUI-Manager"
set "REPO_URL=https://github.com/Comfy-Org/ComfyUI-Manager.git"
set "REPO_NAME=ComfyUI-Manager"
set "LEGACY_OWNER=ltdrdata"
call :sync_repo
if errorlevel 1 goto :failed
if not exist "%REPO_DIR%\requirements.txt" goto :manager_ready
"%VENV_PYTHON%" -m pip install -r "%REPO_DIR%\requirements.txt"
if errorlevel 1 goto :failed
:manager_ready
call :verify_core
if errorlevel 1 goto :failed
"%VENV_PYTHON%" -m pip check
if errorlevel 1 goto :failed

rem ---------------------------------------------------------------------------
rem 6. Optional acceleration packages. Each question defaults to Yes.
rem ---------------------------------------------------------------------------
echo.
echo Choose optional packages. Enter accepts Yes; No preserves existing packages.
echo Installing a package does not automatically enable its kernels in ComfyUI.
call :ask "Install Triton for Windows"
if errorlevel 1 goto :sage
call :install_triton
:sage
call :ask "Install SageAttention 2.2 - requires Triton"
if errorlevel 1 goto :flash
call :ensure_triton
if errorlevel 1 goto :sage_blocked
set "PACKAGE_URL=https://github.com/woct0rdho/SageAttention/releases/download/v2.2.0-windows.post6/sageattention-2.2.0+cu130torch2.10.0andhigher.post6-cp310-abi3-win_amd64.whl"
set "PACKAGE_MODULE=sageattention"
call :install_wheel
set "SAGE_STATUS=%PACKAGE_STATUS%"
goto :flash
:sage_blocked
set "SAGE_STATUS=blocked - Triton unavailable or declined"
set "OPTIONAL_FAILED=1"
:flash
call :ask "Install FlashAttention"
if errorlevel 1 goto :block
set "PACKAGE_URL=https://huggingface.co/Wildminder/AI-windows-whl/resolve/main/flash_attn-2.8.4+d20260328cu130torch2.12.0cxx11abiTRUE-cp313-cp313-win_amd64.whl"
set "PACKAGE_MODULE=flash_attn"
call :install_wheel
set "FLASH_STATUS=%PACKAGE_STATUS%"
:block
call :ask "Install BlockSparseAttention"
if errorlevel 1 goto :sparge
set "PACKAGE_URL=https://huggingface.co/Wildminder/AI-windows-whl/resolve/main/block_sparse_attn/block_sparse_attn-0.0.2.post2+d20260117.cu130torch2.12.1cxx11abiTRUE-cp313-cp313-win_amd64.whl"
set "PACKAGE_MODULE=block_sparse_attn"
call :install_wheel
set "BLOCK_STATUS=%PACKAGE_STATUS%"
:sparge
call :ask "Install SpargeAttn - requires Triton"
if errorlevel 1 goto :launchers
call :ensure_triton
if errorlevel 1 goto :sparge_blocked
set "PACKAGE_URL=https://github.com/woct0rdho/SpargeAttn/releases/download/v0.1.0-windows.post4/spas_sage_attn-0.1.0+cu130torch2.9.0andhigher.post4-cp39-abi3-win_amd64.whl"
set "PACKAGE_MODULE=spas_sage_attn"
call :install_wheel
set "SPARGE_STATUS=%PACKAGE_STATUS%"
goto :launchers
:sparge_blocked
set "SPARGE_STATUS=blocked - Triton unavailable or declined"
set "OPTIONAL_FAILED=1"
:launchers

rem ---------------------------------------------------------------------------
rem 7. Provide launchers, preserve customized copies, and verify the final stack.
rem ---------------------------------------------------------------------------
set "LAUNCHER=comfyui.bat"
call :provision_launcher
if errorlevel 1 goto :failed
set "LAUNCHER=comfyui-start.bat"
call :provision_launcher
if errorlevel 1 goto :failed
call :verify_core
if errorlevel 1 goto :failed
"%VENV_PYTHON%" -m pip check
if errorlevel 1 goto :dependency_failure
echo Dependency check passed.
goto :complete
:dependency_failure
echo WARNING: Final dependency check failed after optional installation.
set "OPTIONAL_FAILED=1"
:complete
set "EXIT_CODE=0"
if "%OPTIONAL_FAILED%"=="1" set "EXIT_CODE=2"
echo.
echo Core installation completed in "%COMFY_DIR%".
echo Python: "%VENV_PYTHON%"
echo Start with "%COMFY_DIR%\comfyui-start.bat".
echo Import checks do not guarantee every GPU kernel or workflow is supported.
goto :finish

rem ---------------------------------------------------------------------------
rem Helpers: prompts, safe repository updates, packages, and launcher delivery.
rem ---------------------------------------------------------------------------

:ask
set "ANSWER="
set /p "ANSWER=%~1? [Y/n] "
if not defined ANSWER exit /b 0
if /i "%ANSWER%"=="y" exit /b 0
if /i "%ANSWER%"=="yes" exit /b 0
if /i "%ANSWER%"=="n" exit /b 1
if /i "%ANSWER%"=="no" exit /b 1
echo Please enter Y or N, or press Enter for Yes.
goto :ask
:sync_repo
if not exist "%REPO_DIR%" goto :clone_repo
echo Validating existing repository "%REPO_DIR%"...
set "REPO_TOP="
set "REPO_REMOTE="
for /f "delims=" %%R in ('git -C "%REPO_DIR%" rev-parse --show-toplevel 2^>nul') do set "REPO_TOP=%%R"
if not defined REPO_TOP exit /b 1
"%BASE_PYTHON%" -c "import os; from pathlib import Path; assert Path(os.environ['REPO_TOP']).resolve() == Path(os.environ['REPO_DIR']).resolve()"
if errorlevel 1 exit /b 1
for /f "delims=" %%R in ('git -C "%REPO_DIR%" remote get-url origin 2^>nul') do set "REPO_REMOTE=%%R"
if not defined REPO_REMOTE exit /b 1
rem Accept canonical and historical upstream URLs, without changing the remote.
set "REPO_REMOTE=%REPO_REMOTE:.git=%"
set "REPO_REMOTE=%REPO_REMOTE:git@github.com:=https://github.com/%"
set "REPO_REMOTE=%REPO_REMOTE:ssh://git@github.com/=https://github.com/%"
if /i "%REPO_REMOTE%"=="https://github.com/Comfy-Org/%REPO_NAME%" goto :update_repo
if /i "%REPO_REMOTE%"=="https://github.com/%LEGACY_OWNER%/%REPO_NAME%" goto :update_repo
echo ERROR: This directory does not have the expected upstream repository.
exit /b 1

:update_repo
git -C "%REPO_DIR%" diff --quiet
if errorlevel 1 goto :dirty_repo
git -C "%REPO_DIR%" diff --cached --quiet
if errorlevel 1 goto :dirty_repo
git -C "%REPO_DIR%" pull --ff-only
exit /b %errorlevel%
:dirty_repo
echo ERROR: Tracked local changes found. Preserve or commit them yourself before updating.
exit /b 1
:clone_repo
git clone "%REPO_URL%" "%REPO_DIR%"
exit /b %errorlevel%
:verify_core
echo Verifying Torch, TorchVision and CUDA...
"%VENV_PYTHON%" -c "import torch; print('Torch:',torch.__version__,'CUDA:',torch.version.cuda); assert torch.__version__ == '2.12.1+cu130' and torch.version.cuda == '13.0'"
if errorlevel 1 exit /b 1
"%VENV_PYTHON%" -c "import torchvision; print('TorchVision:',torchvision.__version__); assert torchvision.__version__ == '0.27.1+cu130'"
if errorlevel 1 exit /b 1
"%VENV_PYTHON%" -c "import torch; assert torch.cuda.is_available(), 'CUDA is not available'; print('CUDA device:',torch.cuda.get_device_name())"
exit /b %errorlevel%

:check_driver
set "DRIVER_FOUND=1"
"%BASE_PYTHON%" -c "import os, re; v=os.environ['DRIVER_VERSION'].strip(); assert re.fullmatch(r'[0-9]+\.[0-9]+',v); assert int(v.split('.')[0]) >= 580"
if errorlevel 1 set "DRIVER_FAILED=1"
exit /b 0
:install_triton
set "TRITON_STATUS=failed"
"%VENV_PYTHON%" -m pip install -U "triton-windows<3.8"
if errorlevel 1 goto :triton_failed
"%VENV_PYTHON%" -c "import triton; print('Triton:',triton.__version__)"
if errorlevel 1 goto :triton_failed
set "TRITON_STATUS=installed"
exit /b 0
:triton_failed
set "OPTIONAL_FAILED=1"
echo WARNING: Triton installation or import failed.
exit /b 1
:ensure_triton
if "%TRITON_STATUS%"=="installed" exit /b 0
if "%TRITON_STATUS%"=="failed" exit /b 1
"%VENV_PYTHON%" -c "import triton; from importlib.metadata import version; from packaging.version import Version; assert Version(version('triton-windows')) < Version('3.8')" >nul 2>&1
if not errorlevel 1 exit /b 0
echo This package requires Triton, which is not available in the selected range.
call :ask "Install the required Triton dependency"
if errorlevel 1 exit /b 1
call :install_triton
exit /b %errorlevel%
:install_wheel
set "PACKAGE_STATUS=failed"
"%VENV_PYTHON%" -m pip install "%PACKAGE_URL%"
if errorlevel 1 goto :wheel_failed
"%VENV_PYTHON%" -c "import importlib, sys; importlib.import_module(sys.argv[1]); print(sys.argv[1] + ': import passed')" "%PACKAGE_MODULE%"
if errorlevel 1 goto :wheel_failed
set "PACKAGE_STATUS=installed"
exit /b 0
:wheel_failed
set "OPTIONAL_FAILED=1"
echo WARNING: %PACKAGE_MODULE% installation or import failed. Continuing independent extras.
exit /b 1
:provision_launcher
if exist "%COMFY_DIR%\%LAUNCHER%" goto :preserve_launcher
set "LAUNCHER_SOURCE=%INSTALLER_DIR%%LAUNCHER%"
if exist "%LAUNCHER_SOURCE%" goto :copy_launcher
set "LAUNCHER_TEMP="
rem Run from Scripts to avoid cmd's nested executable-quote parsing in FOR /F.
pushd "%COMFY_DIR%\.venv\Scripts"
if errorlevel 1 exit /b 1
for /f "delims=" %%T in ('python.exe -c "import tempfile; f=tempfile.NamedTemporaryFile(prefix='comfyui-launcher-',suffix='.bat',delete=False); print(f.name); f.close()"') do set "LAUNCHER_TEMP=%%T"
popd
if not defined LAUNCHER_TEMP exit /b 1
curl.exe --fail --location --retry 2 --output "%LAUNCHER_TEMP%" "https://github.com/silveroxides/ComfyUI-StartScripts/releases/download/%RELEASE_TAG%/%LAUNCHER%"
if errorlevel 1 goto :launcher_failed
set "LAUNCHER_SOURCE=%LAUNCHER_TEMP%"
:copy_launcher
"%VENV_PYTHON%" -c "from pathlib import Path; import os; src=Path(os.environ['LAUNCHER_SOURCE']); data=src.read_bytes(); assert data.lstrip().lower().startswith(b'@echo off'), 'Invalid launcher content'; dst=Path(os.environ['COMFY_DIR'])/os.environ['LAUNCHER']; f=dst.open('xb'); f.write(data); f.close()"
if errorlevel 1 goto :launcher_failed
call :cleanup_launcher
exit /b 0
:launcher_failed
call :cleanup_launcher
echo ERROR: Failed to provision %LAUNCHER%. No failed download was installed.
exit /b 1
:cleanup_launcher
if not defined LAUNCHER_TEMP exit /b 0
"%VENV_PYTHON%" -c "from pathlib import Path; import os; Path(os.environ['LAUNCHER_TEMP']).unlink(missing_ok=True)"
set "LAUNCHER_TEMP="
exit /b 0
:preserve_launcher
echo Preserving existing "%COMFY_DIR%\%LAUNCHER%"; review v7 launcher changes manually.
exit /b 0
:missing_git
echo ERROR: Install Git for Windows from https://git-scm.com/downloads/win and rerun.
goto :finish
:missing_curl
echo ERROR: curl.exe is required for release launcher downloads. Restore Windows curl and rerun.
goto :finish
:bad_python
echo ERROR: Standard x64 CPython 3.13.13 or a later 3.13 patch is required.
echo Python 3.14+, ARM64, 32-bit and free-threaded Python are not supported by these wheels.
echo Install from https://www.python.org/downloads/windows/ and rerun.
echo An existing incompatible .venv is preserved; migrate it manually before rerunning.
goto :finish
:bad_driver
echo ERROR: NVIDIA driver information is missing, invalid, or below the R580 baseline.
echo Install a current driver for your GPU: https://www.nvidia.com/en-us/drivers/
goto :finish
:failed
echo ERROR: Required installation step failed. See the command output above.
echo Existing files and Git changes have not been reset or removed.
:finish
echo.
echo Triton: %TRITON_STATUS%
echo SageAttention: %SAGE_STATUS%
echo FlashAttention: %FLASH_STATUS%
echo BlockSparseAttention: %BLOCK_STATUS%
echo SpargeAttn: %SPARGE_STATUS%
echo Exit code: %EXIT_CODE% - 0 success, 1 core failure, 2 optional failure.
popd
pause
exit /b %EXIT_CODE%
