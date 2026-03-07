#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# run-docker.sh — Build the Docker image, deploy to Kubernetes (minikube),
#                 scale to N pods and open the dashboard.
#
# Usage: ./run-docker.sh [PODS]
#   PODS  number of K8s replicas (default: 4)
#
# Prerequisites: docker, kubectl, minikube  (or an existing cluster)
# ---------------------------------------------------------------------------
set -euo pipefail

APP_NAME="k8s-batch-processor"
IMAGE="wallaceespindola/k8s-batch-processor:latest"
REPLICAS="${1:-4}"
MAX_WAIT=180      # seconds to wait for rollout
PORT_LOCAL=8080

# ── Banner ──────────────────────────────────────────────────────────────────
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

# ── Prereq checks ───────────────────────────────────────────────────────────
for cmd in docker kubectl; do
    command -v "$cmd" &>/dev/null || { echo "[ERROR] '$cmd' not found. Install it first."; exit 1; }
done

# ── Start / verify minikube ──────────────────────────────────────────────────
if command -v minikube &>/dev/null; then
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
    echo "[WARN]  minikube not found — using current kubectl context."
    kubectl cluster-info || { echo "[ERROR] No reachable cluster. Start minikube or configure kubectl."; exit 1; }
fi

# ── Build Docker image ───────────────────────────────────────────────────────
echo "[INFO]  Building Docker image: $IMAGE"
echo "[INFO]  (Maven build runs inside Docker — no local JDK required)"
docker build -t "$IMAGE" .

# ── Patch imagePullPolicy to Never (use local image, no registry) ────────────
# Temporarily patch the deployment to avoid pulling from DockerHub.
# This only affects the running cluster, not the yaml file on disk.
echo "[INFO]  Applying K8s manifests..."
kubectl apply -f k8s/
kubectl patch deployment "$APP_NAME" \
    -p '{"spec":{"template":{"spec":{"containers":[{"name":"k8s-batch-processor","imagePullPolicy":"Never"}]}}}}' \
    2>/dev/null || true

# ── Scale to requested replica count ────────────────────────────────────────
echo "[INFO]  Scaling deployment to $REPLICAS replica(s)..."
kubectl scale deployment "$APP_NAME" --replicas="$REPLICAS"

# ── Wait for all pods to become Ready ───────────────────────────────────────
echo "[INFO]  Waiting for rollout (timeout ${MAX_WAIT}s)..."
kubectl rollout status deployment/"$APP_NAME" --timeout="${MAX_WAIT}s"

# ── Show running pods ────────────────────────────────────────────────────────
echo ""
echo "[INFO]  Running pods:"
kubectl get pods -l app="$APP_NAME" -o wide
echo ""

# ── Expose the service and resolve URL ──────────────────────────────────────
if command -v minikube &>/dev/null; then
    APP_URL=$(minikube service k8s-batch-processor-nodeport --url 2>/dev/null | head -1)
else
    # Generic cluster: port-forward in background
    echo "[INFO]  Starting port-forward → localhost:$PORT_LOCAL ..."
    pkill -f "kubectl port-forward svc/$APP_NAME" 2>/dev/null || true
    kubectl port-forward svc/"$APP_NAME" "$PORT_LOCAL":80 &>/dev/null &
    echo $! > .k8s-portforward.pid
    APP_URL="http://localhost:$PORT_LOCAL"
    sleep 2
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo "[OK]    $APP_NAME is running on Kubernetes ($REPLICAS pod(s))"
echo ""
echo "  Dashboard   --> $APP_URL"
echo "  Swagger UI  --> $APP_URL/swagger-ui.html"
echo "  H2 Console  --> $APP_URL/h2.html"
echo "  Health      --> $APP_URL/actuator/health"
echo ""
echo "  Live pod status  --> kubectl get pods -l app=$APP_NAME -o wide -w"
echo "  Stream logs      --> kubectl logs -l app=$APP_NAME --tail=50 -f"
echo "  Scale replicas   --> kubectl scale deployment $APP_NAME --replicas=N"
echo "  HPA status       --> kubectl get hpa k8s-batch-processor-hpa"
echo ""

open "$APP_URL" 2>/dev/null || xdg-open "$APP_URL" 2>/dev/null || true
