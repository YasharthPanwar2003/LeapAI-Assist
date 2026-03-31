#!/bin/bash
# =============================================================================
# systemd-install.sh — Install/uninstall SUSE AI systemd units
# =============================================================================
# Handles both user-session (--user) and system (--system) installs.
# Automatically detects container runtime (podman or docker).
#
# Usage:
#   ./systemd-install.sh --user                    # Install as user (Podman)
#   ./systemd-install.sh --system                  # Install as root (Docker)
#   ./systemd-install.sh --user --uninstall        # Uninstall user units
#   ./systemd-install.sh --system --uninstall      # Uninstall system units
#   ./systemd-install.sh --status                  # Show current status
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_DIR=""
UNIT_PREFIX=""

MODE="install"
SCOPE="user"
UNINSTALL=false
STATUS_ONLY=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --user)    SCOPE="user" ;;
        --system)  SCOPE="system" ;;
        --uninstall|--remove) UNINSTALL=true ;;
        --status)  STATUS_ONLY=true ;;
        --help|-h)
            echo "Usage: $0 [--user|--system] [--uninstall] [--status]"
            echo ""
            echo "  --user       Install as user session units (Podman, rootless)"
            echo "  --system     Install as system units (Docker, root)"
            echo "  --uninstall  Remove the units"
            echo "  --status     Show current status"
            exit 0
            ;;
        *)
            log_error "Unknown argument: $arg"
            exit 1
            ;;
    esac
done

# --- Status Check ---
if [[ "$STATUS_ONLY" == true ]]; then
    echo -e "\n${BOLD}=== SUSE AI systemd Status ===${NC}\n"

    echo -e "${BOLD}User Session Units:${NC}"
    systemctl --user list-units --type=service,timer,socket 'suse-ai*' 2>/dev/null || \
        echo "  (no user units found)"

    echo -e "\n${BOLD}System Units:${NC}"
    sudo systemctl list-units --type=service,timer,socket 'suse-ai*' 2>/dev/null || \
        echo "  (no system units found)"

    echo -e "\n${BOLD}Active Timers:${NC}"
    systemctl --user list-timers 'suse-ai*' 2>/dev/null || echo "  (no user timers)"
    sudo systemctl list-timers 'suse-ai*' 2>/dev/null || echo "  (no system timers)"

    echo ""
    exit 0
fi

# --- Detect runtime ---
detect_runtime() {
    if command -v podman &>/dev/null; then
        echo "podman"
    elif command -v docker &>/dev/null; then
        echo "docker"
    else
        echo ""
    fi
}

RUNTIME=$(detect_runtime)

# --- Set paths ---
if [[ "$SCOPE" == "user" ]]; then
    SYSTEMD_DIR="$HOME/.config/systemd/user"
    ENV_DIR="$HOME/.config/suse-ai"
    SUDO=""
else
    SYSTEMD_DIR="/etc/systemd/system"
    ENV_DIR="/etc/suse-ai"
    SUDO="sudo"
fi

UNITS=(
    "suse-ai.socket"
    "suse-ai.service"
    "suse-ai-ingest.service"
    "suse-ai-ingest.timer"
)

# --- Uninstall ---
if [[ "$UNINSTALL" == true ]]; then
    log_step "Uninstalling systemd units (scope: $SCOPE)..."

    # Stop and disable timer first
    $SUDO systemctl ${SCOPE:+--$SCOPE} disable --now suse-ai-ingest.timer 2>/dev/null || true
    $SUDO systemctl ${SCOPE:+--$SCOPE} disable --now suse-ai.socket 2>/dev/null || true
    $SUDO systemctl ${SCOPE:+--$SCOPE} stop suse-ai-ingest.service 2>/dev/null || true
    $SUDO systemctl ${SCOPE:+--$SCOPE} stop suse-ai.service 2>/dev/null || true

    # Remove unit files
    for unit in "${UNITS[@]}"; do
        if [[ -f "${SYSTEMD_DIR}/${unit}" ]]; then
            $SUDO rm -f "${SYSTEMD_DIR}/${unit}"
            log_info "Removed ${SYSTEMD_DIR}/${unit}"
        fi
    done

    # Reload daemon
    $SUDO systemctl daemon-reload
    log_info "systemd daemon reloaded"

    # Reset failed state
    $SUDO systemctl ${SCOPE:+--$SCOPE} reset-failed suse-ai* 2>/dev/null || true

    echo -e "${GREEN}${BOLD}Uninstall complete.${NC}"
    exit 0
fi

# --- Install ---
echo -e "\n${BOLD}${BLUE}═══ Installing SUSE AI systemd Units ═══${NC}\n"
echo -e "  Scope:   ${BOLD}${SCOPE}${NC}"
echo -e "  Runtime: ${BOLD}${RUNTIME:-not detected}${NC}"
echo -e "  Target:  ${BOLD}${SYSTEMD_DIR}${NC}"
echo ""

# Check runtime
if [[ -z "$RUNTIME" ]]; then
    log_error "No container runtime found (podman or docker)."
    log_error "Install one first: sudo zypper install podman OR sudo zypper install docker-ce"
    exit 1
fi

# For Docker system installs, copy Docker-specific service
if [[ "$RUNTIME" == "docker" && "$SCOPE" == "system" ]]; then
    log_step "Docker detected — will use deploy/docker/ service files"
fi

# Create directories
log_step "Creating directories..."
$SUDO mkdir -p "$SYSTEMD_DIR"
$SUDO mkdir -p "$ENV_DIR"
log_info "Created ${SYSTEMD_DIR}"
log_info "Created ${ENV_DIR}"

# Copy unit files
log_step "Copying systemd units..."
for unit in "${UNITS[@]}"; do
    if [[ -f "${SCRIPT_DIR}/${unit}" ]]; then
        $SUDO cp "${SCRIPT_DIR}/${unit}" "${SYSTEMD_DIR}/${unit}"
        log_info "Installed ${SYSTEMD_DIR}/${unit}"
    else
        log_warn "File not found: ${SCRIPT_DIR}/${unit} — skipping"
    fi
done

# Copy environment file (if not already present)
if [[ ! -f "${ENV_DIR}/env" ]] && [[ -f "${SCRIPT_DIR}/suse-ai.env" ]]; then
    $SUDO cp "${SCRIPT_DIR}/suse-ai.env" "${ENV_DIR}/env"
    log_info "Created ${ENV_DIR}/env (edit this to configure your environment)"
else
    log_info "Environment file already exists at ${ENV_DIR}/env — not overwriting"
fi

# For Docker system installs, also install Docker-specific units
if [[ "$RUNTIME" == "docker" && "$SCOPE" == "system" ]]; then
    DOCKER_DIR="${SCRIPT_DIR}/../docker"
    if [[ -f "${DOCKER_DIR}/suse-ai-docker.service" ]]; then
        $SUDO cp "${DOCKER_DIR}/suse-ai-docker.service" "${SYSTEMD_DIR}/"
        $SUDO cp "${DOCKER_DIR}/suse-ai-docker.socket" "${SYSTEMD_DIR}/"
        log_info "Installed Docker-specific systemd units"
        log_warn "NOTE: suse-ai-docker.service overrides the generic suse-ai.service"
    fi
fi

# Reload systemd
log_step "Reloading systemd daemon..."
$SUDO systemctl daemon-reload

# Enable socket activation (starts service on first connection)
log_step "Enabling socket activation..."
$SUDO systemctl ${SCOPE:+--$SCOPE} enable suse-ai.socket
log_info "Socket activation enabled on port 8090"

# Enable the ingest timer (nightly re-indexing)
log_step "Enabling nightly ingest timer..."
$SUDO systemctl ${SCOPE:+--$SCOPE} enable suse-ai-ingest.timer
log_info "Ingest timer enabled (runs daily at 03:00)"

# Summary
echo -e "\n${BOLD}${GREEN}═══ Installation Complete ═══${NC}\n"
echo -e "  Units installed to: ${BOLD}${SYSTEMD_DIR}${NC}"
echo -e "  Environment file:   ${BOLD}${ENV_DIR}/env${NC}"
echo ""
echo -e "  ${BOLD}Available commands:${NC}"
echo -e "    Status:      ${YELLOW}systemctl ${SCOPE:+--$SCOPE} status suse-ai.socket${NC}"
echo -e "    Logs:        ${YELLOW}journalctl ${SCOPE:+--$SCOPE} -u suse-ai -f${NC}"
echo -e "    Test:        ${YELLOW}curl http://localhost:8090/health${NC}"
echo -e "    Ingest now:  ${YELLOW}systemctl ${SCOPE:+--$SCOPE} start suse-ai-ingest${NC}"
echo -e "    Uninstall:   ${YELLOW}$0 --${SCOPE} --uninstall${NC}"
echo ""
