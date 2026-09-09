@echo off
setlocal DisableDelayedExpansion
if not defined PYTHON set "PYTHON=python"
if defined GIT_PATH set "PATH=%GIT_PATH%;%PATH%"
if not defined VENV_DIR set "VENV_DIR=%~dp0.venv"
set "EXIT_CODE=1"
set "REQUIREMENTS_CHANGED="
set "OLD_HEAD="
pushd "%~dp0"
if errorlevel 1 exit /b 1
if not exist tmp mkdir tmp
if not exist tmp goto :failed
set "COMFYUI_RESTART=tmp/restart"
set "ERROR_REPORTING=FALSE"
set "update_choice="
set /p "update_choice=Update ComfyUI? [y/N] "
if /i "%update_choice%"=="y" goto :update
if /i "%update_choice%"=="yes" goto :update
goto :start_venv

:update
git diff --quiet
if errorlevel 1 goto :update_failed
git diff --cached --quiet
if errorlevel 1 goto :update_failed
for /f "delims=" %%H in ('git rev-parse HEAD') do set "OLD_HEAD=%%H"
if not defined OLD_HEAD goto :update_failed
git pull --ff-only
if errorlevel 1 goto :update_failed
git diff --quiet "%OLD_HEAD%" HEAD -- requirements.txt
if errorlevel 2 goto :update_failed
if errorlevel 1 set "REQUIREMENTS_CHANGED=1"
echo Update complete.

:start_venv
if "%VENV_DIR%"=="-" goto :check_python
if "%SKIP_VENV%"=="1" goto :check_python
if exist "%VENV_DIR%\Scripts\python.exe" goto :activate_venv
if exist "%VENV_DIR%" goto :failed
"%PYTHON%" -m venv "%VENV_DIR%" >tmp/stdout.txt 2>tmp/stderr.txt
if errorlevel 1 goto :show_stdout_stderr

:activate_venv
call "%VENV_DIR%\Scripts\activate.bat"
if errorlevel 1 goto :failed
set "PYTHON=%VENV_DIR%\Scripts\python.exe"

:check_python
"%PYTHON%" -m pip --version >tmp/stdout.txt 2>tmp/stderr.txt
if not errorlevel 1 goto :requirements
if not defined PIP_INSTALLER_LOCATION goto :show_stdout_stderr
"%PYTHON%" "%PIP_INSTALLER_LOCATION%" >tmp/stdout.txt 2>tmp/stderr.txt
if errorlevel 1 goto :show_stdout_stderr
"%PYTHON%" -m pip --version >tmp/stdout.txt 2>tmp/stderr.txt
if errorlevel 1 goto :show_stdout_stderr

:requirements
if not defined REQUIREMENTS_CHANGED goto :launch
"%PYTHON%" -m pip install -r requirements.txt
if errorlevel 1 goto :failed
goto :launch

:launch
"%PYTHON%" main.py %COMMANDLINE_ARGS% %*
set "EXIT_CODE=%errorlevel%"
if exist "%COMFYUI_RESTART%" goto :launch
goto :finish

:update_failed
echo ERROR: Update failed or tracked local changes exist. No automatic stash or reset was performed.
goto :finish
:show_stdout_stderr
if exist tmp/stdout.txt type tmp/stdout.txt
if exist tmp/stderr.txt type tmp/stderr.txt
:failed
echo ERROR: Startup failed. See output above.
:finish
popd
pause
exit /b %EXIT_CODE%
