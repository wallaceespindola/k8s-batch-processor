@echo off
:: ---------------------------------------------------------------------------
:: run.bat — Build (if needed) and start the K8s Batch Processor in background
:: ---------------------------------------------------------------------------
setlocal EnableDelayedExpansion

set APP_NAME=k8s-batch-processor
set PID_FILE=.app.pid
set LOG_FILE=app.log
set PORT=8080
set HEALTH_URL=http://localhost:%PORT%/actuator/health
set MAX_WAIT=60

:: ── Banner ──────────────────────────────────────────────────────────────────
echo.
echo =====================================================
echo   Starting %APP_NAME%
echo =====================================================

:: ── Guard: already running? ─────────────────────────────────────────────────
if exist "%PID_FILE%" (
    set /p SAVED_PID=<"%PID_FILE%"
    for /f "tokens=1" %%i in ('tasklist /fi "PID eq !SAVED_PID!" /fo csv /nh 2^>nul') do (
        if not "%%~i"=="" (
            echo [WARN]  %APP_NAME% is already running (PID !SAVED_PID!)
            echo [WARN]  Dashboard: http://localhost:%PORT%
            exit /b 0
        )
    )
    del /f "%PID_FILE%" >nul 2>&1
)

:: ── Guard: port already in use? ─────────────────────────────────────────────
for /f "tokens=5" %%a in ('netstat -ano 2^>nul ^| findstr ":%PORT% " ^| findstr "LISTENING"') do (
    echo [ERROR] Port %PORT% is already in use (PID %%a).
    echo [ERROR] Stop that process first, or change server.port in application.yml.
    exit /b 1
)

:: ── Find or build JAR ───────────────────────────────────────────────────────
set JAR=
for %%f in (target\*.jar) do set JAR=%%f

if not defined JAR (
    echo [INFO]  No JAR found -- building...
    call mvn clean package -DskipTests --no-transfer-progress -q
    if errorlevel 1 (
        echo [ERROR] Build failed. Check Maven output above.
        exit /b 1
    )
    for %%f in (target\*.jar) do set JAR=%%f
)

echo [INFO]  JAR  : %JAR%
echo [INFO]  Port : %PORT%
echo [INFO]  Log  : %LOG_FILE%
echo.

:: ── Start in background ──────────────────────────────────────────────────────
start /b "" java -Djava.security.egd=file:/dev/./urandom -jar "%JAR%" > "%LOG_FILE%" 2>&1

:: Capture PID of the java process just started
timeout /t 2 /nobreak >nul
for /f "tokens=2 delims=," %%a in (
    'tasklist /fi "imagename eq java.exe" /fo csv /nh 2^>nul'
) do (
    set APP_PID=%%~a
    goto :pid_found
)

:pid_found
echo !APP_PID!> "%PID_FILE%"
echo [INFO]  Process started (PID !APP_PID!) -- waiting for health check...

:: ── Poll health endpoint ─────────────────────────────────────────────────────
set elapsed=0
:health_loop
if %elapsed% geq %MAX_WAIT% goto :timeout

:: Use PowerShell for the HTTP check (available on all modern Windows)
for /f "delims=" %%r in (
    'powershell -NoProfile -Command "(Invoke-WebRequest -Uri '%HEALTH_URL%' -UseBasicParsing -ErrorAction SilentlyContinue).Content" 2^>nul'
) do set RESPONSE=%%r

echo !RESPONSE! | findstr /c:"UP" >nul 2>&1
if not errorlevel 1 goto :healthy

timeout /t 2 /nobreak >nul
set /a elapsed+=2
set /p =.< nul
goto :health_loop

:healthy
echo.
echo [OK]    %APP_NAME% is UP after %elapsed%s
echo.
echo   Dashboard   --^> http://localhost:%PORT%
echo   Swagger UI  --^> http://localhost:%PORT%/swagger-ui.html
echo   H2 Console  --^> http://localhost:%PORT%/h2-console
echo   Health      --^> http://localhost:%PORT%/actuator/health
echo   Logs        --^> type %LOG_FILE%
echo.
exit /b 0

:timeout
echo.
echo [ERROR] App did not become healthy within %MAX_WAIT%s.
echo [ERROR] Check logs: type %LOG_FILE%
exit /b 1
