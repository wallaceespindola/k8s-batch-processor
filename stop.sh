#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# stop.sh — Gracefully stop the K8s Batch Processor
# ---------------------------------------------------------------------------
set -euo pipefail

APP_NAME="k8s-batch-processor"
PID_FILE=".app.pid"
PORT=8080
GRACEFUL_TIMEOUT=20   # seconds before sending SIGKILL

# ── Colour helpers ──────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  🛑  Stopping ${APP_NAME}${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# ── Resolve PID ─────────────────────────────────────────────────────────────
PID=""

if [[ -f "$PID_FILE" ]]; then
    PID=$(cat "$PID_FILE")
    if ! kill -0 "$PID" 2>/dev/null; then
        warn "PID file found but process ${PID} is not running."
        rm -f "$PID_FILE"
        PID=""
    fi
fi

# Fallback: find by port
if [[ -z "$PID" ]]; then
    PID=$(lsof -iTCP:"${PORT}" -sTCP:LISTEN -t 2>/dev/null | head -1 || true)
    if [[ -n "$PID" ]]; then
        info "Found process on port ${PORT}: PID ${PID}"
    fi
fi

if [[ -z "$PID" ]]; then
    warn "${APP_NAME} does not appear to be running."
    exit 0
fi

# ── Graceful shutdown (SIGTERM → wait → SIGKILL) ─────────────────────────────
info "Sending SIGTERM to PID ${PID}..."
kill -TERM "$PID" 2>/dev/null || true

elapsed=0
while kill -0 "$PID" 2>/dev/null; do
    if [[ $elapsed -ge $GRACEFUL_TIMEOUT ]]; then
        warn "Process did not stop after ${GRACEFUL_TIMEOUT}s — sending SIGKILL..."
        kill -KILL "$PID" 2>/dev/null || true
        sleep 1
        break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
    printf '.'
done

echo ""
rm -f "$PID_FILE"

if kill -0 "$PID" 2>/dev/null; then
    error "Failed to stop process ${PID}."
    exit 1
fi

success "${APP_NAME} stopped (was PID ${PID})"
echo ""
