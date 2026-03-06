# ---------------------------------------------------------------------------
# run.ps1 — Build (if needed) and start the K8s Batch Processor in background
# ---------------------------------------------------------------------------
# Usage: .\run.ps1
# Requires PowerShell 5.1+ (pre-installed on Windows 10/11)
# ---------------------------------------------------------------------------
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$APP_NAME      = 'k8s-batch-processor'
$PID_FILE      = '.app.pid'
$LOG_FILE      = 'app.log'
$PORT          = 8080
$HEALTH_URL    = "http://localhost:$PORT/actuator/health"
$MAX_WAIT      = 60

# ── Banner ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "====================================================="
Write-Host "  Starting $APP_NAME"
Write-Host "====================================================="

# ── Guard: already running? ─────────────────────────────────────────────────
if (Test-Path $PID_FILE) {
    $savedPid = [int](Get-Content $PID_FILE -Raw).Trim()
    $proc = Get-Process -Id $savedPid -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "[WARN]  $APP_NAME is already running (PID $savedPid)"
        Write-Host "[WARN]  Dashboard: http://localhost:$PORT"
        exit 0
    }
    Remove-Item $PID_FILE -Force
}

# ── Guard: port already in use? ─────────────────────────────────────────────
$listener = Get-NetTCPConnection -LocalPort $PORT -State Listen -ErrorAction SilentlyContinue
if ($listener) {
    Write-Host "[ERROR] Port $PORT is already in use (PID $($listener[0].OwningProcess))."
    Write-Host "[ERROR] Stop that process first, or change server.port in application.yml."
    exit 1
}

# ── Find or build JAR ───────────────────────────────────────────────────────
$jar = Get-ChildItem -Path 'target' -Filter '*.jar' -ErrorAction SilentlyContinue |
       Where-Object { $_.Name -notlike '*-sources.jar' } |
       Select-Object -First 1

if (-not $jar) {
    Write-Host "[INFO]  No JAR found -- building..."
    & mvn clean package -DskipTests --no-transfer-progress -q
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Build failed. Check Maven output above."
        exit 1
    }
    $jar = Get-ChildItem -Path 'target' -Filter '*.jar' |
           Where-Object { $_.Name -notlike '*-sources.jar' } |
           Select-Object -First 1
}

Write-Host "[INFO]  JAR  : $($jar.FullName)"
Write-Host "[INFO]  Port : $PORT"
Write-Host "[INFO]  Log  : $LOG_FILE"
Write-Host ""

# ── Start in background ──────────────────────────────────────────────────────
$proc = Start-Process -FilePath 'java' `
    -ArgumentList "-jar", $jar.FullName `
    -RedirectStandardOutput $LOG_FILE `
    -RedirectStandardError  $LOG_FILE `
    -NoNewWindow -PassThru

$proc.Id | Set-Content $PID_FILE
Write-Host "[INFO]  Process started (PID $($proc.Id)) -- waiting for health check..."

# ── Poll health endpoint ─────────────────────────────────────────────────────
$elapsed = 0
Write-Host -NoNewline "[INFO]  "
while ($elapsed -lt $MAX_WAIT) {
    Start-Sleep -Seconds 2
    $elapsed += 2
    Write-Host -NoNewline '.'

    try {
        $resp = Invoke-WebRequest -Uri $HEALTH_URL -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        if ($resp.Content -match '"UP"') { break }
    } catch { <# not ready yet #> }
}
Write-Host ""

if ($elapsed -ge $MAX_WAIT) {
    Write-Host ""
    Write-Host "[ERROR] App did not become healthy within ${MAX_WAIT}s."
    Write-Host "[ERROR] Check logs: Get-Content $LOG_FILE -Tail 50"
    exit 1
}

Write-Host ""
Write-Host "[OK]    $APP_NAME is UP after ${elapsed}s"
Write-Host ""
Write-Host "  Dashboard   --> http://localhost:$PORT"
Write-Host "  Swagger UI  --> http://localhost:$PORT/swagger-ui.html"
Write-Host "  H2 Console  --> http://localhost:$PORT/h2.html"
Write-Host "  Health      --> http://localhost:$PORT/actuator/health"
Write-Host "  Logs        --> Get-Content $LOG_FILE -Tail 50 -Wait"
Write-Host ""
