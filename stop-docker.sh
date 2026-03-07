#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# stop-docker.sh — Remove K8s resources deployed by run-docker.sh.
#                  minikube itself is left running (pass --stop-minikube
#                  to also stop it, --delete-minikube to destroy it).
#
# Usage: ./stop-docker.sh [--stop-minikube | --delete-minikube]
# ---------------------------------------------------------------------------
set -euo pipefail

APP_NAME="k8s-batch-processor"
ACTION="${1:-}"

# ── Banner ──────────────────────────────────────────────────────────────────
echo ""
echo "====================================================="
echo "  K8s Batch Processor — Kubernetes Teardown"
echo "====================================================="

# ── Kill any port-forward ────────────────────────────────────────────────────
if [ -f .k8s-portforward.pid ]; then
    PF_PID=$(cat .k8s-portforward.pid)
    kill "$PF_PID" 2>/dev/null && echo "[INFO]  Port-forward (PID $PF_PID) stopped."
    rm -f .k8s-portforward.pid
fi
pkill -f "kubectl port-forward svc/$APP_NAME" 2>/dev/null || true

# ── Delete K8s resources ─────────────────────────────────────────────────────
if kubectl get deployment "$APP_NAME" &>/dev/null; then
    kubectl delete -f k8s/ --ignore-not-found=true
    echo "[OK]    K8s resources deleted."
else
    echo "[INFO]  No K8s resources found for $APP_NAME."
fi

# ── Optionally stop / delete minikube ────────────────────────────────────────
if command -v minikube &>/dev/null; then
    case "$ACTION" in
        --stop-minikube)
            echo "[INFO]  Stopping minikube..."
            minikube stop
            echo "[OK]    minikube stopped."
            ;;
        --delete-minikube)
            echo "[INFO]  Deleting minikube cluster..."
            minikube delete
            echo "[OK]    minikube cluster deleted."
            ;;
        *)
            echo ""
            echo "[INFO]  minikube is still running."
            echo "        To pause  : minikube stop"
            echo "        To destroy: minikube delete"
            ;;
    esac
fi

echo ""
