@echo off
:: ---------------------------------------------------------------------------
:: run.bat — Build (if needed) and start the K8s Batch Processor in background
:: ---------------------------------------------------------------------------
setlocal EnableDelayedExpansion

set APP_NAME=k8s-batch-processor
set PID_FILE=.app.pid
set LOG_FILE=app.log
set PORT=8080
set MAX_WAIT=60

:: ── Banner ──────────────────────────────────────────────────────────────────
echo.
echo =====================================================
echo   Starting %APP_NAME%
echo =====================================================

:: ── Guard: already running? ─────────────────────────────────────────────────
if exist "%PID_FILE%" (
    set /p SAVED_PID=<"%PID_FILE%"
    tasklist /fi "PID eq !SAVED_PID!" /fo csv /nh 2>nul | findstr /i "java" >nul 2>&1
    if not errorlevel 1 (
        echo [WARN]  %APP_NAME% is already running (PID !SAVED_PID!)
        echo [WARN]  Dashboard: http://localhost:%PORT%
        exit /b 0
    )
    del /f "%PID_FILE%" >nul 2>&1
)

:: ── Guard: port already in use? ─────────────────────────────────────────────
netstat -ano 2>nul | findstr ":%PORT% " | findstr "LISTENING" >nul 2>&1
if not errorlevel 1 (
    echo [ERROR] Port %PORT% is already in use.
    echo [ERROR] Stop that process first, or change server.port in application.yml.
    exit /b 1
)

:: ── Find or build JAR ───────────────────────────────────────────────────────
set JAR=
for %%f in (target\*.jar) do (
    echo %%f | findstr /v "sources" >nul 2>&1 && set JAR=%%f
)

if not defined JAR (
    echo [INFO]  No JAR found -- building...
    call mvn clean package -DskipTests --no-transfer-progress -q
    if errorlevel 1 (
        echo [ERROR] Build failed. Check Maven output above.
        exit /b 1
    )
    for %%f in (target\*.jar) do (
        echo %%f | findstr /v "sources" >nul 2>&1 && set JAR=%%f
    )
)

echo [INFO]  JAR  : %JAR%
echo [INFO]  Port : %PORT%
echo [INFO]  Log  : %LOG_FILE%
echo.

:: ── Start in background, capture PID via PowerShell ─────────────────────────
:: PowerShell's Start-Process -PassThru gives us the PID reliably.
for /f %%p in ('powershell -NoProfile -Command "$p = Start-Process java -ArgumentList '-jar','%JAR%' -RedirectStandardOutput '%LOG_FILE%' -RedirectStandardError '%LOG_FILE%' -NoNewWindow -PassThru; $p.Id"') do set APP_PID=%%p

if not defined APP_PID (
    echo [ERROR] Failed to start the application.
    exit /b 1
)

echo !APP_PID!> "%PID_FILE%"
echo [INFO]  Process started (PID !APP_PID!) -- waiting for health check...

:: ── Poll health endpoint ─────────────────────────────────────────────────────
:: Write response to a temp file to avoid single-quote conflicts inside for /f.
set elapsed=0
set HEALTH_TMP=%TEMP%\_k8sbatch_health.tmp

:health_loop
if %elapsed% geq %MAX_WAIT% goto :timeout

timeout /t 2 /nobreak >nul
set /a elapsed+=2
set /p =.< nul

powershell -NoProfile -Command "try { (Invoke-WebRequest -Uri http://localhost:%PORT%/actuator/health -UseBasicParsing).Content } catch { '' }" > "%HEALTH_TMP%" 2>nul
findstr /c:"UP" "%HEALTH_TMP%" >nul 2>&1
if not errorlevel 1 goto :healthy

goto :health_loop

:healthy
echo.
if exist "%HEALTH_TMP%" del /f "%HEALTH_TMP%" >nul 2>&1
echo [OK]    %APP_NAME% is UP after %elapsed%s
echo.
echo   Dashboard   --^> http://localhost:%PORT%
echo   Swagger UI  --^> http://localhost:%PORT%/swagger-ui.html
echo   H2 Console  --^> http://localhost:%PORT%/h2.html
echo   Health      --^> http://localhost:%PORT%/actuator/health
echo   Logs        --^> type %LOG_FILE%
echo.
exit /b 0

:timeout
echo.
if exist "%HEALTH_TMP%" del /f "%HEALTH_TMP%" >nul 2>&1
echo [ERROR] App did not become healthy within %MAX_WAIT%s.
echo [ERROR] Check logs: type %LOG_FILE%
exit /b 1
