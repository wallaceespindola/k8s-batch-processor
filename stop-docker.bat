@echo off
:: ---------------------------------------------------------------------------
:: stop-docker.bat — Remove K8s resources deployed by run-docker.bat.
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

:: ── Kill any port-forward ────────────────────────────────────────────────────
for /f "tokens=5" %%p in ('netstat -ano 2^>nul ^| findstr ":8080 " ^| findstr "LISTENING"') do (
    tasklist /fi "PID eq %%p" /fi "imagename eq kubectl.exe" /fo csv /nh 2>nul | findstr "kubectl" >nul 2>&1
    if not errorlevel 1 (
        taskkill /pid %%p /f >nul 2>&1
        echo [INFO]  Port-forward stopped.
    )
)

:: ── Delete K8s resources ─────────────────────────────────────────────────────
kubectl get deployment %APP_NAME% >nul 2>&1
if not errorlevel 1 (
    kubectl delete -f k8s/ --ignore-not-found=true
    echo [OK]    K8s resources deleted.
) else (
    echo [INFO]  No K8s resources found for %APP_NAME%.
)

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
)
echo.
