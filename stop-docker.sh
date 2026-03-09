#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# stop-docker.sh — Remove K8s resources deployed by run-docker.sh.
#                  The runtime (colima/minikube) is left running unless you
#                  pass an explicit flag:
#                    --stop-colima    / --stop-minikube
#                    --delete-colima  / --delete-minikube
#
# Usage: ./stop-docker.sh [--stop-colima | --delete-colima |
#                          --stop-minikube | --delete-minikube]
# ---------------------------------------------------------------------------
set -euo pipefail

APP_NAME="k8s-batch-processor"
ACTION="${1:-}"

# ── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo "====================================================="
echo "  K8s Batch Processor — Kubernetes Teardown"
echo "====================================================="

# ── Resolve kubectl command ──────────────────────────────────────────────────
if command -v kubectl &>/dev/null; then
    KUBECTL="kubectl"
elif command -v kubectl.lima &>/dev/null; then
    KUBECTL="kubectl.lima"
else
    KUBECTL=""
    echo "[WARN]  kubectl not found — skipping K8s resource deletion."
fi

# ── Kill any port-forward ────────────────────────────────────────────────────
if [ -f .k8s-portforward.pid ]; then
    PF_PID=$(cat .k8s-portforward.pid)
    kill "$PF_PID" 2>/dev/null && echo "[INFO]  Port-forward (PID $PF_PID) stopped."
    rm -f .k8s-portforward.pid
fi
pkill -f "kubectl port-forward svc/$APP_NAME" 2>/dev/null || true
pkill -f "kubectl.lima port-forward svc/$APP_NAME" 2>/dev/null || true

# ── Delete K8s resources ──────────────────────────────────────────────────────
if [[ -n "$KUBECTL" ]]; then
    if "$KUBECTL" get deployment "$APP_NAME" &>/dev/null; then
        "$KUBECTL" delete -f k8s/ --ignore-not-found=true
        echo "[OK]    K8s resources deleted."
    else
        echo "[INFO]  No K8s resources found for $APP_NAME."
    fi
fi

# ── Optionally stop / delete colima ──────────────────────────────────────────
if command -v colima &>/dev/null; then
    case "$ACTION" in
        --stop-colima)
            echo "[INFO]  Stopping colima..."
            colima stop
            echo "[OK]    colima stopped."
            ;;
        --delete-colima)
            echo "[INFO]  Deleting colima instance..."
            colima delete
            echo "[OK]    colima instance deleted."
            ;;
        --stop-minikube|--delete-minikube)
            echo "[WARN]  minikube flags ignored — this system uses colima."
            ;;
        *)
            echo ""
            echo "[INFO]  colima is still running."
            echo "        To stop   : colima stop"
            echo "        To destroy: colima delete"
            ;;
    esac
# ── Optionally stop / delete minikube ────────────────────────────────────────
elif command -v minikube &>/dev/null; then
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
