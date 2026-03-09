@echo off
:: ---------------------------------------------------------------------------
:: stop-docker.bat — Remove K8s resources deployed by run-docker.bat.
::                   The runtime is left running unless you pass a flag.
::
:: Usage: stop-docker.bat [--stop-minikube | --delete-minikube]
:: ---------------------------------------------------------------------------
setlocal EnableDelayedExpansion

set APP_NAME=k8s-batch-processor
set ACTION=%~1

echo.
echo =====================================================
echo   K8s Batch Processor -- Kubernetes Teardown
echo =====================================================

:: ── Check kubectl ─────────────────────────────────────────────────────────────
where kubectl >nul 2>&1
if errorlevel 1 (
    echo [WARN]  kubectl not found -- skipping K8s resource deletion.
    goto :runtime_teardown
)

:: ── Kill any port-forward ─────────────────────────────────────────────────────
:: First try the saved PID (most precise)
if exist .k8s-portforward.pid (
    set /p PF_PID=<.k8s-portforward.pid
    taskkill /pid !PF_PID! /f >nul 2>&1 && echo [INFO]  Port-forward (PID !PF_PID!) stopped.
    del /f .k8s-portforward.pid >nul 2>&1
)
:: Fallback: kill kubectl processes whose command line contains 'port-forward'
:: Uses PowerShell+CIM so only the port-forward kubectl is targeted, not all kubectl
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='kubectl.exe'\" | Where-Object { $_.CommandLine -like '*port-forward*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; Write-Host '[INFO]  kubectl port-forward process stopped.' }" 2>nul

:: ── Delete K8s resources ──────────────────────────────────────────────────────
kubectl get deployment %APP_NAME% >nul 2>&1
if not errorlevel 1 (
    kubectl delete -f k8s/ --ignore-not-found=true
    echo [OK]    K8s resources deleted.
) else (
    echo [INFO]  No K8s resources found for %APP_NAME%.
)

:runtime_teardown
:: ── Optionally stop / delete minikube ────────────────────────────────────────
where minikube >nul 2>&1
if not errorlevel 1 (
    if "!ACTION!"=="--stop-minikube" (
        echo [INFO]  Stopping minikube...
        minikube stop
        echo [OK]    minikube stopped.
    ) else if "!ACTION!"=="--delete-minikube" (
        echo [INFO]  Deleting minikube cluster...
        minikube delete
        echo [OK]    minikube cluster deleted.
    ) else (
        echo.
        echo [INFO]  minikube is still running.
        echo         To pause  : minikube stop
        echo         To destroy: minikube delete
    )
) else (
    echo.
    echo [INFO]  Runtime: Docker Desktop or external cluster (no action taken).
    echo         To stop Kubernetes: disable it in Docker Desktop Settings.
)
echo.
