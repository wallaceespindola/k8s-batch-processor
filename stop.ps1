# ---------------------------------------------------------------------------
# stop.ps1 — Gracefully stop the K8s Batch Processor
# ---------------------------------------------------------------------------
# Usage: .\stop.ps1
# Requires PowerShell 5.1+ (pre-installed on Windows 10/11)
# ---------------------------------------------------------------------------
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$APP_NAME         = 'k8s-batch-processor'
$PID_FILE         = '.app.pid'
$PORT             = 8080
$GRACEFUL_TIMEOUT = 20

# ── Banner ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "====================================================="
Write-Host "  Stopping $APP_NAME"
Write-Host "====================================================="

$appPid = $null

# ── Resolve PID from file ────────────────────────────────────────────────────
if (Test-Path $PID_FILE) {
    $savedPid = [int](Get-Content $PID_FILE -Raw).Trim()
    $proc = Get-Process -Id $savedPid -ErrorAction SilentlyContinue
    if ($proc) {
        $appPid = $savedPid
    } else {
        Write-Host "[WARN]  PID file found but process $savedPid is not running."
        Remove-Item $PID_FILE -Force
    }
}

# ── Fallback: find java process listening on PORT ────────────────────────────
if (-not $appPid) {
    $conn = Get-NetTCPConnection -LocalPort $PORT -State Listen -ErrorAction SilentlyContinue |
            Select-Object -First 1
    if ($conn) {
        $candidate = $conn.OwningProcess
        $proc = Get-Process -Id $candidate -ErrorAction SilentlyContinue
        if ($proc -and $proc.ProcessName -like '*java*') {
            $appPid = $candidate
            Write-Host "[INFO]  Found java process on port ${PORT}: PID $appPid"
        }
    }
}

if (-not $appPid) {
    Write-Host "[WARN]  $APP_NAME does not appear to be running."
    exit 0
}

# ── Graceful stop ────────────────────────────────────────────────────────────
Write-Host "[INFO]  Stopping PID $appPid gracefully..."
Stop-Process -Id $appPid -ErrorAction SilentlyContinue

$elapsed = 0
Write-Host -NoNewline "[INFO]  Waiting  "
while ($elapsed -lt $GRACEFUL_TIMEOUT) {
    Start-Sleep -Seconds 1
    $elapsed++
    Write-Host -NoNewline '.'
    $still = Get-Process -Id $appPid -ErrorAction SilentlyContinue
    if (-not $still) { break }
}
Write-Host ""

# ── Force kill if still alive ────────────────────────────────────────────────
$still = Get-Process -Id $appPid -ErrorAction SilentlyContinue
if ($still) {
    Write-Host "[WARN]  Process did not stop after ${GRACEFUL_TIMEOUT}s -- forcing termination..."
    Stop-Process -Id $appPid -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# ── Cleanup ──────────────────────────────────────────────────────────────────
if (Test-Path $PID_FILE) { Remove-Item $PID_FILE -Force }

$final = Get-Process -Id $appPid -ErrorAction SilentlyContinue
if ($final) {
    Write-Host "[ERROR] Failed to stop process $appPid."
    exit 1
}

Write-Host "[OK]    $APP_NAME stopped (was PID $appPid)"
Write-Host ""
