@echo off
REM Copy e2e.dll to mIRC folder after build

set MIRC_PATH=C:\mIRC
set DLL_DEBUG=Debug\e2e.dll
set DLL_RELEASE=Release\e2e.dll
set MRC_FILE=e2e.mrc

echo Copying e2e.dll to mIRC...

if exist "%DLL_RELEASE%" (
    echo Found Release build
    copy /Y "%DLL_RELEASE%" "%MIRC_PATH%\e2e.dll"
    if %errorlevel% equ 0 (
        echo SUCCESS: Release DLL copied to %MIRC_PATH%
    ) else (
        echo ERROR: Failed to copy Release DLL
    )
) else if exist "%DLL_DEBUG%" (
    echo Found Debug build
    copy /Y "%DLL_DEBUG%" "%MIRC_PATH%\e2e.dll"
    if %errorlevel% equ 0 (
        echo SUCCESS: Debug DLL copied to %MIRC_PATH%
    ) else (
        echo ERROR: Failed to copy Debug DLL
    )
) else (
    echo ERROR: No DLL found. Build the project first.
)

echo Copying e2e.mrc to mIRC...
if exist "%MRC_FILE%" (
    copy /Y "%MRC_FILE%" "%MIRC_PATH%\e2e.mrc"
    if %errorlevel% equ 0 (
        echo SUCCESS: e2e.mrc copied to %MIRC_PATH%
    ) else (
        echo ERROR: Failed to copy e2e.mrc
    )
) else (
    echo ERROR: e2e.mrc not found in project root.
)

pause
