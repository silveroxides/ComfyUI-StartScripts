rem @echo off

if not defined PYTHON (set PYTHON=python)
if defined GIT_PATH (set "PATH=%GIT_PATH%;%PATH%")

mkdir tmp 2>NUL

set "update_choice="
set /p "update_choice=Update ComfyUI? [y/N] "
if /i not "%update_choice%"=="y" goto :start_venv

echo Checking for local changes...
set STASHED_CHANGES=0
git status | findstr /C:"Changes not staged for commit" >nul
if %ERRORLEVEL% == 0 (
    echo Uncommitted changes found. Stashing...
    git stash
    set STASHED_CHANGES=1
)

echo Fetching updates...
git fetch
echo Pulling updates...
git pull > tmp/pull_output.txt
type tmp/pull_output.txt

findstr /C:"requirements.txt" tmp/pull_output.txt >nul
if %ERRORLEVEL% == 0 (
    echo requirements.txt updated. Will install dependencies.
    set REQUIREMENTS_CHANGED=1
)

if %STASHED_CHANGES% == 1 (
    echo Applying stashed changes...
    git stash apply
)

echo Update complete.

if not defined VENV_DIR (set "VENV_DIR=%~dp0%venv")

set COMFYUI_RESTART=tmp/restart
set ERROR_REPORTING=FALSE

%PYTHON% -c "" >tmp/stdout.txt 2>tmp/stderr.txt
if %ERRORLEVEL% == 0 goto :check_pip
echo Couldn't launch python
goto :show_stdout_stderr

:check_pip
%PYTHON% -mpip --help >tmp/stdout.txt 2>tmp/stderr.txt
if %ERRORLEVEL% == 0 goto :start_venv
if "%PIP_INSTALLER_LOCATION%" == "" goto :show_stdout_stderr
%PYTHON% "%PIP_INSTALLER_LOCATION%" >tmp/stdout.txt 2>tmp/stderr.txt
if %ERRORLEVEL% == 0 goto :start_venv
echo Couldn't install pip
goto :show_stdout_stderr

:start_venv
if ["%VENV_DIR%"] == ["-"] goto :skip_venv
if ["%SKIP_VENV%"] == ["1"] goto :skip_venv

dir "%VENV_DIR%\Scripts\Python.exe" >tmp/stdout.txt 2>tmp/stderr.txt
if %ERRORLEVEL% == 0 goto :activate_venv

for /f "delims=" %%i in ('CALL %PYTHON% -c "import sys; print(sys.executable)"') do set PYTHON_FULLNAME="%%i"
echo Creating venv in directory %VENV_DIR% using python %PYTHON_FULLNAME%
%PYTHON_FULLNAME% -m venv "%VENV_DIR%" >tmp/stdout.txt 2>tmp/stderr.txt
if %ERRORLEVEL% == 0 goto :activate_venv
echo Unable to create venv in directory "%VENV_DIR%"
goto :show_stdout_stderr

:activate_venv
set PYTHON="%VENV_DIR%\Scripts\Python.exe"
call "%VENV_DIR%\Scripts\activate.bat"
echo venv %PYTHON%

if defined REQUIREMENTS_CHANGED (
    echo Installing/updating Python dependencies...
    %PYTHON% -m pip install -r requirements.txt
)

:skip_venv
goto :launch


:launch
%PYTHON% main.py %COMMANDLINE_ARGS% %*
if EXIST tmp/restart goto :skip_venv
pause
exit /b

:show_stdout_stderr

echo.
echo exit code: %errorlevel%

for /f %%i in ("tmp\stdout.txt") do set size=%%~zi
if %size% equ 0 goto :show_stderr
echo.
echo stdout:
type tmp\stdout.txt

:show_stderr
for /f %%i in ("tmp\stderr.txt") do set size=%%~zi
if %size% equ 0 goto :show_stderr
echo.
echo stderr:
type tmp\stderr.txt

:endofscript

echo.
echo Launch unsuccessful. Exiting.
pause
