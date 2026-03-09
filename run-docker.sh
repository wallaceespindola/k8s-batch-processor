#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# run-docker.sh — Build the Docker image, deploy to Kubernetes (colima),
#                 scale to N pods and open the dashboard.
#
# Usage: ./run-docker.sh [PODS]
#   PODS  number of K8s replicas (default: 4)
#
# Prerequisites: docker, kubectl (or kubectl.lima), colima (or minikube)
# ---------------------------------------------------------------------------
set -euo pipefail

APP_NAME="k8s-batch-processor"
IMAGE="wallaceespindola/k8s-batch-processor:latest"
REPLICAS="${1:-4}"
MAX_WAIT=300      # seconds to wait for rollout
PORT_LOCAL=8080

# ── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo "====================================================="
echo "  K8s Batch Processor — Kubernetes Deploy"
echo "  Pods (replicas) : $REPLICAS"
echo "====================================================="
echo ""
echo "NOTE: In this POC each K8s pod runs the full Spring Boot app."
echo "      Batch partitioning is thread-based WITHIN the pod that"
echo "      serves your request. Set 'Number of Pods' in the dashboard"
echo "      to control how many worker threads (partitions) that pod uses."
echo "      For true multi-pod distribution a shared DB + remote"
echo "      partitioning (Kafka) would be required."
echo ""

# ── Resolve kubectl command ──────────────────────────────────────────────────
if command -v kubectl &>/dev/null; then
    KUBECTL="kubectl"
elif command -v kubectl.lima &>/dev/null; then
    # kubectl.lima is Lima's own binary for limactl VMs — it is NOT compatible
    # with colima's Kubernetes (colima manages its own kubeconfig via standard kubectl).
    echo "[ERROR] Found 'kubectl.lima' but colima Kubernetes requires the standard 'kubectl'."
    echo "        Install it with:  brew install kubectl"
    echo "        Then rerun this script."
    exit 1
else
    echo "[ERROR] 'kubectl' not found. Install it with: brew install kubectl"
    exit 1
fi

# ── Check docker ─────────────────────────────────────────────────────────────
command -v docker &>/dev/null || { echo "[ERROR] 'docker' not found. Install colima + docker."; exit 1; }

# ── Start / verify Kubernetes runtime ───────────────────────────────────────
USE_COLIMA=false
USE_MINIKUBE=false

if command -v colima &>/dev/null; then
    USE_COLIMA=true

    # Check if colima is running
    if colima status 2>/dev/null | grep -qi "running"; then
        echo "[INFO]  colima is already running."
        # Check if Kubernetes is actually reachable; restart with --kubernetes if not
        if ! "$KUBECTL" cluster-info &>/dev/null 2>&1; then
            echo "[INFO]  Kubernetes not reachable — restarting colima with Kubernetes enabled..."
            colima stop
            colima start --kubernetes --cpu 4 --memory 8
        fi
    else
        echo "[INFO]  Starting colima with Kubernetes enabled (cpus=4 memory=8g)..."
        colima start --kubernetes --cpu 4 --memory 8
    fi

    # Set Docker context to colima
    if docker context inspect colima &>/dev/null; then
        docker context use colima 2>/dev/null || true
    fi
    echo "[INFO]  Docker context: $(docker context show 2>/dev/null || echo 'default')"

elif command -v minikube &>/dev/null; then
    USE_MINIKUBE=true
    MK_STATUS=$(minikube status -f '{{.Host}}' 2>/dev/null || echo "Stopped")
    if [[ "$MK_STATUS" != "Running" ]]; then
        echo "[INFO]  Starting minikube (cpus=4 memory=4g)..."
        minikube start --cpus=4 --memory=4g --driver=docker
    else
        echo "[INFO]  minikube is already running."
    fi
    # Point local Docker CLI at minikube's daemon so the image is available
    # to the cluster without a registry push.
    echo "[INFO]  Pointing Docker at minikube's daemon..."
    eval "$(minikube docker-env)"

else
    echo "[WARN]  Neither colima nor minikube found — using current kubectl context."
    "$KUBECTL" cluster-info || { echo "[ERROR] No reachable cluster. Install colima or minikube."; exit 1; }
fi

# ── Build Docker image ───────────────────────────────────────────────────────
echo "[INFO]  Building Docker image: $IMAGE"
echo "[INFO]  (Maven build runs inside Docker — no local JDK required)"
docker build -t "$IMAGE" .

# ── Apply K8s manifests ──────────────────────────────────────────────────────
echo "[INFO]  Applying K8s manifests..."
"$KUBECTL" apply -f k8s/

# ── Patch imagePullPolicy to Never (use local image, no registry) ────────────
# Avoids pulling from DockerHub when the image was built locally.
echo "[INFO]  Patching imagePullPolicy to Never (local image)..."
"$KUBECTL" patch deployment "$APP_NAME" \
    -p '{"spec":{"template":{"spec":{"containers":[{"name":"k8s-batch-processor","imagePullPolicy":"Never"}]}}}}' \
    2>/dev/null || true

# ── Scale to requested replica count ─────────────────────────────────────────
echo "[INFO]  Scaling deployment to $REPLICAS replica(s)..."
"$KUBECTL" scale deployment "$APP_NAME" --replicas="$REPLICAS"

# ── Wait for all pods to become Ready ────────────────────────────────────────
echo "[INFO]  Waiting for rollout (timeout ${MAX_WAIT}s)..."
"$KUBECTL" rollout status deployment/"$APP_NAME" --timeout="${MAX_WAIT}s"

# ── Show running pods ─────────────────────────────────────────────────────────
echo ""
echo "[INFO]  Running pods:"
"$KUBECTL" get pods -l app="$APP_NAME" -o wide
echo ""

# ── Expose the service and resolve URL ───────────────────────────────────────
if [[ "$USE_COLIMA" == "true" ]]; then
    # colima: use port-forward in background (NodePort on colima VM is not
    # reachable from macOS host without extra network config)
    echo "[INFO]  Starting port-forward → localhost:$PORT_LOCAL ..."
    pkill -f "kubectl.*port-forward.*$APP_NAME" 2>/dev/null || true
    pkill -f "kubectl.lima.*port-forward.*$APP_NAME" 2>/dev/null || true
    "$KUBECTL" port-forward svc/"$APP_NAME" "$PORT_LOCAL":80 &>/dev/null &
    echo $! > .k8s-portforward.pid
    APP_URL="http://localhost:$PORT_LOCAL"
    sleep 3   # give port-forward time to establish

elif [[ "$USE_MINIKUBE" == "true" ]]; then
    APP_URL=$(minikube service k8s-batch-processor-nodeport --url 2>/dev/null | head -1)
    if [[ -z "$APP_URL" ]]; then
        echo "[WARN]  Could not get minikube service URL, falling back to port-forward..."
        pkill -f "kubectl.*port-forward.*$APP_NAME" 2>/dev/null || true
        "$KUBECTL" port-forward svc/"$APP_NAME" "$PORT_LOCAL":80 &>/dev/null &
        echo $! > .k8s-portforward.pid
        APP_URL="http://localhost:$PORT_LOCAL"
        sleep 2
    fi

else
    # Generic cluster: port-forward in background
    echo "[INFO]  Starting port-forward → localhost:$PORT_LOCAL ..."
    pkill -f "kubectl.*port-forward.*$APP_NAME" 2>/dev/null || true
    "$KUBECTL" port-forward svc/"$APP_NAME" "$PORT_LOCAL":80 &>/dev/null &
    echo $! > .k8s-portforward.pid
    APP_URL="http://localhost:$PORT_LOCAL"
    sleep 2
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo "[OK]    $APP_NAME is running on Kubernetes ($REPLICAS pod(s))"
echo ""
echo "  Dashboard   --> $APP_URL"
echo "  Swagger UI  --> $APP_URL/swagger-ui.html"
echo "  H2 Console  --> $APP_URL/h2.html"
echo "  Health      --> $APP_URL/actuator/health"
echo ""
echo "  Live pod status  --> $KUBECTL get pods -l app=$APP_NAME -o wide -w"
echo "  Stream logs      --> $KUBECTL logs -l app=$APP_NAME --tail=50 -f"
echo "  Scale replicas   --> $KUBECTL scale deployment $APP_NAME --replicas=N"
echo "  HPA status       --> $KUBECTL get hpa k8s-batch-processor-hpa"
echo ""

open "$APP_URL" 2>/dev/null || xdg-open "$APP_URL" 2>/dev/null || true