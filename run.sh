#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# run.sh — Build (if needed) and start the K8s Batch Processor in background
# ---------------------------------------------------------------------------
set -euo pipefail

APP_NAME="k8s-batch-processor"
PID_FILE=".app.pid"
LOG_FILE="app.log"
PORT=8080
HEALTH_URL="http://localhost:${PORT}/actuator/health"
MAX_WAIT=60   # seconds to wait for startup

# ── Colour helpers ──────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

# ── Guard: already running? ─────────────────────────────────────────────────
if [[ -f "$PID_FILE" ]]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        warn "${APP_NAME} is already running (PID ${PID})"
        warn "Dashboard → http://localhost:${PORT}"
        exit 0
    else
        rm -f "$PID_FILE"
    fi
fi

# ── Guard: port already in use? ─────────────────────────────────────────────
if lsof -iTCP:"${PORT}" -sTCP:LISTEN -t &>/dev/null; then
    error "Port ${PORT} is already in use by another process."
    error "Stop that process first, or change server.port in application.yml."
    exit 1
fi

# ── Build if JAR is missing or sources changed ──────────────────────────────
JAR=$(ls target/*.jar 2>/dev/null | head -1 || true)
if [[ -z "$JAR" ]]; then
    info "No JAR found — building..."
    mvn clean package -DskipTests --no-transfer-progress -q
    JAR=$(ls target/*.jar | head -1)
fi

# ── Start ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  🚀  Starting ${APP_NAME}${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
info "JAR     : ${JAR}"
info "Port    : ${PORT}"
info "Log     : ${LOG_FILE}"
echo ""

nohup java \
    -XX:+UseContainerSupport \
    -XX:MaxRAMPercentage=75.0 \
    -Djava.security.egd=file:/dev/./urandom \
    -jar "$JAR" \
    > "$LOG_FILE" 2>&1 &

APP_PID=$!
echo "$APP_PID" > "$PID_FILE"
info "Process started (PID ${APP_PID}) — waiting for health check..."

# ── Wait for health endpoint ─────────────────────────────────────────────────
elapsed=0
while [[ $elapsed -lt $MAX_WAIT ]]; do
    if curl -sf "$HEALTH_URL" | grep -q '"status":"UP"'; then
        echo ""
        success "${APP_NAME} is UP after ${elapsed}s"
        echo ""
        echo -e "  ${BOLD}Dashboard   ${RESET}→ ${CYAN}http://localhost:${PORT}${RESET}"
        echo -e "  ${BOLD}Swagger UI  ${RESET}→ ${CYAN}http://localhost:${PORT}/swagger-ui.html${RESET}"
        echo -e "  ${BOLD}H2 Console  ${RESET}→ ${CYAN}http://localhost:${PORT}/h2-console${RESET}"
        echo -e "  ${BOLD}Health      ${RESET}→ ${CYAN}http://localhost:${PORT}/actuator/health${RESET}"
        echo -e "  ${BOLD}Logs        ${RESET}→ tail -f ${LOG_FILE}"
        echo ""
        exit 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
    printf '.'
done

echo ""
error "App did not become healthy within ${MAX_WAIT}s."
error "Check logs: tail -f ${LOG_FILE}"
exit 1
