@echo off
:: ---------------------------------------------------------------------------
:: stop.bat — Gracefully stop the K8s Batch Processor
:: ---------------------------------------------------------------------------
setlocal EnableDelayedExpansion

set APP_NAME=k8s-batch-processor
set PID_FILE=.app.pid
set PORT=8080
set GRACEFUL_TIMEOUT=20

:: ── Banner ──────────────────────────────────────────────────────────────────
echo.
echo =====================================================
echo   Stopping %APP_NAME%
echo =====================================================

set PID=

:: ── Resolve PID from file ────────────────────────────────────────────────────
if exist "%PID_FILE%" (
    set /p PID=<"%PID_FILE%"

    :: Verify the process is still alive
    set ALIVE=
    for /f "tokens=1" %%i in (
        'tasklist /fi "PID eq !PID!" /fo csv /nh 2^>nul'
    ) do set ALIVE=%%~i

    if not defined ALIVE (
        echo [WARN]  PID file found but process !PID! is not running.
        del /f "%PID_FILE%" >nul 2>&1
        set PID=
    )
)

:: ── Fallback: find java.exe listening on PORT ────────────────────────────────
if not defined PID (
    for /f "tokens=5" %%a in (
        'netstat -ano 2^>nul ^| findstr ":%PORT% " ^| findstr "LISTENING"'
    ) do (
        set CANDIDATE=%%a
        :: Check it's a java process
        for /f "tokens=1" %%j in (
            'tasklist /fi "PID eq !CANDIDATE!" /fi "imagename eq java.exe" /fo csv /nh 2^>nul'
        ) do (
            set PID=!CANDIDATE!
            echo [INFO]  Found java process on port %PORT%: PID !PID!
        )
        if defined PID goto :pid_resolved
    )
)

:pid_resolved
if not defined PID (
    echo [WARN]  %APP_NAME% does not appear to be running.
    exit /b 0
)

:: ── Graceful stop: taskkill /PID (sends WM_CLOSE / CTRL_C_EVENT) ─────────────
echo [INFO]  Stopping PID !PID! gracefully...
taskkill /pid !PID! >nul 2>&1

set elapsed=0
:wait_loop
:: Check if process is still running
set STILL_RUNNING=
for /f "tokens=1" %%i in (
    'tasklist /fi "PID eq !PID!" /fo csv /nh 2^>nul'
) do set STILL_RUNNING=%%~i

if not defined STILL_RUNNING goto :stopped

if %elapsed% geq %GRACEFUL_TIMEOUT% (
    echo.
    echo [WARN]  Process did not stop after %GRACEFUL_TIMEOUT%s -- forcing termination...
    taskkill /f /pid !PID! >nul 2>&1
    timeout /t 2 /nobreak >nul
    goto :stopped
)

timeout /t 1 /nobreak >nul
set /a elapsed+=1
set /p =.< nul
goto :wait_loop

:stopped
echo.
if exist "%PID_FILE%" del /f "%PID_FILE%" >nul 2>&1

:: Final check
set FINAL=
for /f "tokens=1" %%i in (
    'tasklist /fi "PID eq !PID!" /fo csv /nh 2^>nul'
) do set FINAL=%%~i

if defined FINAL (
    echo [ERROR] Failed to stop process !PID!.
    exit /b 1
)

echo [OK]    %APP_NAME% stopped (was PID !PID!)
echo.
exit /b 0
