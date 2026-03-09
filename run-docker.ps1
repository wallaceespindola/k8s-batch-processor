# ---------------------------------------------------------------------------
# run-docker.ps1 — Build the Docker image, deploy to Kubernetes,
#                  scale to N pods and open the dashboard.
#
# Usage: .\run-docker.ps1 [-Pods 4]
#
# Prerequisites: docker, kubectl
#   Runtime (pick one): minikube  OR  Docker Desktop with Kubernetes enabled
# ---------------------------------------------------------------------------
#Requires -Version 5.1
param(
    [int]$Pods = 4
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$APP_NAME   = 'k8s-batch-processor'
$IMAGE      = 'wallaceespindola/k8s-batch-processor:latest'
$MAX_WAIT   = 300
$PORT_LOCAL = 8080
$UseMinikube = $false

# ── Banner ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "====================================================="
Write-Host "  K8s Batch Processor — Kubernetes Deploy"
Write-Host "  Pods (replicas) : $Pods"
Write-Host "====================================================="
Write-Host ""
Write-Host "NOTE: In this POC each K8s pod runs the full Spring Boot app."
Write-Host "      Batch partitioning is thread-based WITHIN the pod that"
Write-Host "      serves your request. Set 'Number of Pods' in the dashboard"
Write-Host "      to control how many worker threads that pod uses."
Write-Host ""

# ── Check docker ─────────────────────────────────────────────────────────────
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] 'docker' not found. Install Docker Desktop."
    exit 1
}

# ── Check kubectl ─────────────────────────────────────────────────────────────
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] 'kubectl' not found."
    Write-Host "        Install options:"
    Write-Host "          - Docker Desktop (enable Kubernetes in Settings)"
    Write-Host "          - winget install -e --id Kubernetes.kubectl"
    exit 1
}

# ── Detect and start Kubernetes runtime ──────────────────────────────────────
if (Get-Command minikube -ErrorAction SilentlyContinue) {
    $UseMinikube = $true
    $mkStatus = (minikube status -f '{{.Host}}' 2>$null)
    if ($mkStatus -ne 'Running') {
        Write-Host "[INFO]  Starting minikube (cpus=4 memory=4g)..."
        minikube start --cpus=4 --memory=4g --driver=docker
    } else {
        Write-Host "[INFO]  minikube is already running."
    }
    # Point Docker CLI at minikube's internal daemon so the locally built
    # image is visible to the cluster (minikube has its own Docker daemon).
    Write-Host "[INFO]  Pointing Docker at minikube's daemon..."
    & minikube docker-env --shell powershell | Invoke-Expression
} else {
    # Fallback: Docker Desktop Kubernetes or any pre-configured cluster.
    # Docker Desktop shares the host Docker daemon — no docker-env needed.
    Write-Host "[INFO]  minikube not found — checking current kubectl context..."
    try {
        kubectl cluster-info | Out-Null
        Write-Host "[INFO]  Using current kubectl context (Docker Desktop or remote cluster)."
    } catch {
        Write-Host "[ERROR] No reachable Kubernetes cluster."
        Write-Host "        Options:"
        Write-Host "          - Install minikube:       winget install minikube"
        Write-Host "          - Enable Kubernetes in Docker Desktop Settings"
        exit 1
    }
}

# ── Build Docker image ───────────────────────────────────────────────────────
Write-Host "[INFO]  Building Docker image: $IMAGE"
Write-Host "[INFO]  (Maven build runs inside Docker — no local JDK required)"
docker build -t $IMAGE .

# ── Apply manifests ───────────────────────────────────────────────────────────
Write-Host "[INFO]  Applying K8s manifests..."
kubectl apply -f k8s/

# ── Patch imagePullPolicy to Never (use local image, no registry) ─────────────
Write-Host "[INFO]  Patching imagePullPolicy to Never (local image)..."
kubectl patch deployment $APP_NAME `
    -p '{"spec":{"template":{"spec":{"containers":[{"name":"k8s-batch-processor","imagePullPolicy":"Never"}]}}}}' `
    2>$null

# ── Scale ────────────────────────────────────────────────────────────────────
Write-Host "[INFO]  Scaling deployment to $Pods replica(s)..."
kubectl scale deployment $APP_NAME --replicas=$Pods

# ── Wait for rollout ─────────────────────────────────────────────────────────
Write-Host "[INFO]  Waiting for rollout (timeout ${MAX_WAIT}s)..."
kubectl rollout status "deployment/$APP_NAME" --timeout="${MAX_WAIT}s"

# ── Show pods ─────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[INFO]  Running pods:"
kubectl get pods -l app=$APP_NAME -o wide
Write-Host ""

# ── Resolve URL ───────────────────────────────────────────────────────────────
$appUrl = $null
if ($UseMinikube) {
    $appUrl = (minikube service k8s-batch-processor-nodeport --url 2>$null | Select-Object -First 1)
}
if (-not $appUrl) {
    Write-Host "[INFO]  Starting port-forward → localhost:$PORT_LOCAL ..."
    # Kill only kubectl processes whose command line contains 'port-forward' (not all kubectl)
    if (Test-Path '.k8s-portforward.pid') {
        $oldPid = [int](Get-Content '.k8s-portforward.pid' -Raw).Trim()
        Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
        Remove-Item '.k8s-portforward.pid' -Force -ErrorAction SilentlyContinue
    }
    Get-CimInstance Win32_Process -Filter "Name='kubectl.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*port-forward*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    $pf = Start-Process kubectl `
        -ArgumentList "port-forward", "svc/$APP_NAME", "${PORT_LOCAL}:80" `
        -PassThru -NoNewWindow
    $pf.Id | Set-Content '.k8s-portforward.pid'
    Start-Sleep -Seconds 3
    $appUrl = "http://localhost:$PORT_LOCAL"
}

# ── Done ─────────────────────────────────────────────────────────────────────
Write-Host "[OK]    $APP_NAME is running on Kubernetes ($Pods pod(s))"
Write-Host ""
Write-Host "  Dashboard   --> $appUrl"
Write-Host "  Swagger UI  --> $appUrl/swagger-ui.html"
Write-Host "  H2 Console  --> $appUrl/h2.html"
Write-Host "  Health      --> $appUrl/actuator/health"
Write-Host ""
Write-Host "  Live pod status --> kubectl get pods -l app=$APP_NAME -o wide -w"
Write-Host "  Stream logs     --> kubectl logs -l app=$APP_NAME --tail=50 -f"
Write-Host "  Scale replicas  --> kubectl scale deployment $APP_NAME --replicas=N"
Write-Host "  HPA status      --> kubectl get hpa k8s-batch-processor-hpa"
Write-Host ""

Start-Process $appUrl
