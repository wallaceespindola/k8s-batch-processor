@echo off
:: ---------------------------------------------------------------------------
:: run-docker.bat — Build the Docker image, deploy to Kubernetes,
::                  scale to N pods and open the dashboard.
::
:: Usage: run-docker.bat [PODS]
::   PODS  number of K8s replicas (default: 4)
::
:: Prerequisites: docker, kubectl
::   Runtime (pick one): minikube  OR  Docker Desktop with Kubernetes enabled
:: ---------------------------------------------------------------------------
setlocal EnableDelayedExpansion

set APP_NAME=k8s-batch-processor
set IMAGE=wallaceespindola/k8s-batch-processor:latest
set REPLICAS=%~1
if not defined REPLICAS set REPLICAS=4
set MAX_WAIT=300
set PORT_LOCAL=8080
set USE_MINIKUBE=0

:: ── Banner ───────────────────────────────────────────────────────────────────
echo.
echo =====================================================
echo   K8s Batch Processor -- Kubernetes Deploy
echo   Pods (replicas) : %REPLICAS%
echo =====================================================
echo.
echo NOTE: In this POC each K8s pod runs the full Spring Boot app.
echo       Batch partitioning is thread-based WITHIN the pod that
echo       serves your request. Set 'Number of Pods' in the dashboard
echo       to control how many worker threads that pod uses.
echo.

:: ── Check docker ─────────────────────────────────────────────────────────────
where docker >nul 2>&1 || (echo [ERROR] docker not found. Install Docker Desktop. & exit /b 1)

:: ── Check kubectl ─────────────────────────────────────────────────────────────
where kubectl >nul 2>&1
if errorlevel 1 (
    echo [ERROR] kubectl not found.
    echo         Install options:
    echo           - Docker Desktop (enable Kubernetes in Settings)
    echo           - winget install -e --id Kubernetes.kubectl
    exit /b 1
)

:: ── Detect and start Kubernetes runtime ──────────────────────────────────────
where minikube >nul 2>&1
if not errorlevel 1 (
    set USE_MINIKUBE=1
    for /f "delims=" %%s in ('minikube status -f "{{.Host}}" 2^>nul') do set MK_STATUS=%%s
    if not "!MK_STATUS!"=="Running" (
        echo [INFO]  Starting minikube (cpus=4 memory=4g)...
        minikube start --cpus=4 --memory=4g --driver=docker
    ) else (
        echo [INFO]  minikube is already running.
    )
    :: Point Docker CLI at minikube's internal daemon so the locally built
    :: image is visible to the cluster (minikube has its own Docker daemon).
    echo [INFO]  Pointing Docker at minikube's daemon...
    for /f "delims=" %%e in ('minikube docker-env --shell cmd 2^>nul') do %%e
) else (
    :: Fallback: Docker Desktop Kubernetes or any pre-configured cluster.
    :: Docker Desktop shares the host Docker daemon — no docker-env needed.
    echo [INFO]  minikube not found — checking current kubectl context...
    kubectl cluster-info >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] No reachable Kubernetes cluster.
        echo         Options:
        echo           - Install minikube:       winget install minikube
        echo           - Enable Kubernetes in Docker Desktop Settings
        exit /b 1
    )
    echo [INFO]  Using current kubectl context (Docker Desktop or remote cluster).
)

:: ── Build Docker image ───────────────────────────────────────────────────────
echo [INFO]  Building Docker image: %IMAGE%
echo [INFO]  (Maven build runs inside Docker -- no local JDK required)
docker build -t %IMAGE% .

:: ── Apply manifests ───────────────────────────────────────────────────────────
echo [INFO]  Applying K8s manifests...
kubectl apply -f k8s/

:: ── Patch imagePullPolicy to Never (use local image, no registry) ─────────────
echo [INFO]  Patching imagePullPolicy to Never (local image)...
kubectl patch deployment %APP_NAME% -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"k8s-batch-processor\",\"imagePullPolicy\":\"Never\"}]}}}}" >nul 2>&1

:: ── Scale ────────────────────────────────────────────────────────────────────
echo [INFO]  Scaling deployment to %REPLICAS% replica(s)...
kubectl scale deployment %APP_NAME% --replicas=%REPLICAS%

:: ── Wait for rollout ─────────────────────────────────────────────────────────
echo [INFO]  Waiting for rollout (timeout %MAX_WAIT%s)...
kubectl rollout status deployment/%APP_NAME% --timeout=%MAX_WAIT%s

:: ── Show pods ─────────────────────────────────────────────────────────────────
echo.
echo [INFO]  Running pods:
kubectl get pods -l app=%APP_NAME% -o wide
echo.

:: ── Resolve URL ───────────────────────────────────────────────────────────────
set APP_URL=
if "!USE_MINIKUBE!"=="1" (
    for /f "delims=" %%u in ('minikube service k8s-batch-processor-nodeport --url 2^>nul') do set APP_URL=%%u
)
if not defined APP_URL (
    echo [INFO]  Starting port-forward to localhost:%PORT_LOCAL%...
    :: Kill any existing kubectl port-forward for this service (by command line, not all kubectl)
    powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='kubectl.exe'\" | Where-Object { $_.CommandLine -like '*port-forward*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }" 2>nul
    if exist .k8s-portforward.pid (
        set /p OLD_PID=<.k8s-portforward.pid
        taskkill /pid !OLD_PID! /f >nul 2>&1
        del /f .k8s-portforward.pid >nul 2>&1
    )
    :: Launch port-forward via PowerShell so we can capture the PID reliably
    for /f %%p in ('powershell -NoProfile -Command "$p = Start-Process kubectl -ArgumentList \"port-forward\",\"svc/%APP_NAME%\",\"%PORT_LOCAL%:80\" -PassThru -NoNewWindow; $p.Id"') do set PF_PID=%%p
    echo !PF_PID!> .k8s-portforward.pid
    timeout /t 3 /nobreak >nul
    set APP_URL=http://localhost:%PORT_LOCAL%
)

:: ── Done ─────────────────────────────────────────────────────────────────────
echo [OK]    %APP_NAME% is running on Kubernetes (%REPLICAS% pod(s))
echo.
echo   Dashboard   --^> !APP_URL!
echo   Swagger UI  --^> !APP_URL!/swagger-ui.html
echo   H2 Console  --^> !APP_URL!/h2.html
echo   Health      --^> !APP_URL!/actuator/health
echo.
echo   Live pod status --^> kubectl get pods -l app=%APP_NAME% -o wide -w
echo   Stream logs     --^> kubectl logs -l app=%APP_NAME% --tail=50 -f
echo   Scale replicas  --^> kubectl scale deployment %APP_NAME% --replicas=N
echo   HPA status      --^> kubectl get hpa k8s-batch-processor-hpa
echo.

start "" "!APP_URL!"
