# ---------------------------------------------------------------------------
# stop-docker.ps1 — Remove K8s resources deployed by run-docker.ps1.
#
# Usage: .\stop-docker.ps1 [-StopMinikube] [-DeleteMinikube]
# ---------------------------------------------------------------------------
#Requires -Version 5.1
param(
    [switch]$StopMinikube,
    [switch]$DeleteMinikube
)
$ErrorActionPreference = 'SilentlyContinue'

$APP_NAME = 'k8s-batch-processor'

Write-Host ""
Write-Host "====================================================="
Write-Host "  K8s Batch Processor — Kubernetes Teardown"
Write-Host "====================================================="

# ── Kill any port-forward ────────────────────────────────────────────────────
if (Test-Path '.k8s-portforward.pid') {
    $pfPid = [int](Get-Content '.k8s-portforward.pid' -Raw).Trim()
    Stop-Process -Id $pfPid -Force -ErrorAction SilentlyContinue
    Write-Host "[INFO]  Port-forward stopped."
    Remove-Item '.k8s-portforward.pid' -Force
}
Get-Process kubectl -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*port-forward*" } |
    Stop-Process -Force -ErrorAction SilentlyContinue

# ── Delete K8s resources ─────────────────────────────────────────────────────
$exists = kubectl get deployment $APP_NAME 2>$null
if ($exists) {
    kubectl delete -f k8s/ --ignore-not-found=true
    Write-Host "[OK]    K8s resources deleted."
} else {
    Write-Host "[INFO]  No K8s resources found for $APP_NAME."
}

# ── Optionally stop / delete minikube ────────────────────────────────────────
if (Get-Command minikube -ErrorAction SilentlyContinue) {
    if ($DeleteMinikube) {
        Write-Host "[INFO]  Deleting minikube cluster..."
        minikube delete
        Write-Host "[OK]    minikube cluster deleted."
    } elseif ($StopMinikube) {
        Write-Host "[INFO]  Stopping minikube..."
        minikube stop
        Write-Host "[OK]    minikube stopped."
    } else {
        Write-Host ""
        Write-Host "[INFO]  minikube is still running."
        Write-Host "        To pause  : minikube stop"
        Write-Host "        To destroy: minikube delete"
        Write-Host "        Or rerun  : .\stop-docker.ps1 -StopMinikube"
    }
}

Write-Host ""
