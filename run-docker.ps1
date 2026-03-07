# ---------------------------------------------------------------------------
# run-docker.ps1 — Build the Docker image, deploy to Kubernetes (minikube),
#                  scale to N pods and open the dashboard.
#
# Usage: .\run-docker.ps1 [-Pods 4]
#
# Prerequisites: docker, kubectl, minikube  (or an existing cluster)
# ---------------------------------------------------------------------------
#Requires -Version 5.1
param(
    [int]$Pods = 4
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$APP_NAME  = 'k8s-batch-processor'
$IMAGE     = 'wallaceespindola/k8s-batch-processor:latest'
$MAX_WAIT  = 180
$PORT_LOCAL = 8080

# ── Banner ──────────────────────────────────────────────────────────────────
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

# ── Prereq checks ───────────────────────────────────────────────────────────
foreach ($cmd in @('docker', 'kubectl')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Host "[ERROR] '$cmd' not found. Install it first."
        exit 1
    }
}

# ── Start / verify minikube ──────────────────────────────────────────────────
if (Get-Command minikube -ErrorAction SilentlyContinue) {
    $mkStatus = (minikube status -f '{{.Host}}' 2>$null)
    if ($mkStatus -ne 'Running') {
        Write-Host "[INFO]  Starting minikube (cpus=4 memory=4g)..."
        minikube start --cpus=4 --memory=4g --driver=docker
    } else {
        Write-Host "[INFO]  minikube is already running."
    }
    Write-Host "[INFO]  Pointing Docker at minikube's daemon..."
    & minikube docker-env --shell powershell | Invoke-Expression
} else {
    Write-Host "[WARN]  minikube not found — using current kubectl context."
    kubectl cluster-info | Out-Null
}

# ── Build Docker image ───────────────────────────────────────────────────────
Write-Host "[INFO]  Building Docker image: $IMAGE"
Write-Host "[INFO]  (Maven build runs inside Docker — no local JDK required)"
docker build -t $IMAGE .

# ── Apply manifests + patch imagePullPolicy ──────────────────────────────────
Write-Host "[INFO]  Applying K8s manifests..."
kubectl apply -f k8s/
kubectl patch deployment $APP_NAME `
    -p '{"spec":{"template":{"spec":{"containers":[{"name":"k8s-batch-processor","imagePullPolicy":"Never"}]}}}}' `
    2>$null

# ── Scale ────────────────────────────────────────────────────────────────────
Write-Host "[INFO]  Scaling deployment to $Pods replica(s)..."
kubectl scale deployment $APP_NAME --replicas=$Pods

# ── Wait for rollout ─────────────────────────────────────────────────────────
Write-Host "[INFO]  Waiting for rollout (timeout ${MAX_WAIT}s)..."
kubectl rollout status "deployment/$APP_NAME" --timeout="${MAX_WAIT}s"

# ── Show pods ────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[INFO]  Running pods:"
kubectl get pods -l app=$APP_NAME -o wide
Write-Host ""

# ── Resolve URL ──────────────────────────────────────────────────────────────
$appUrl = $null
if (Get-Command minikube -ErrorAction SilentlyContinue) {
    $appUrl = (minikube service k8s-batch-processor-nodeport --url 2>$null | Select-Object -First 1)
}
if (-not $appUrl) {
    Write-Host "[INFO]  Starting port-forward → localhost:$PORT_LOCAL ..."
    Get-Process kubectl -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*port-forward*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    $pf = Start-Process kubectl -ArgumentList "port-forward svc/$APP_NAME ${PORT_LOCAL}:80" -PassThru -NoNewWindow
    $pf.Id | Set-Content '.k8s-portforward.pid'
    Start-Sleep -Seconds 2
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
