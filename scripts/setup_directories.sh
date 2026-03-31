#!/bin/bash
# =============================================================================
# openSUSE AI Assistant - Directory Setup Script
# Platform: openSUSE Leap 16 | Python 3.13
# Creates all required directories and sets ownership
# Usage: sudo ./scripts/setup_directories.sh
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ─── Configuration ───
BASE_DIR="/var/lib/suse-ai"
MODEL_DIR="${BASE_DIR}/models"
INDEX_DIR="${BASE_DIR}/index"
CACHE_DIR="${BASE_DIR}/cache/docs"
STATE_DIR="${BASE_DIR}/state"
LOG_DIR="${BASE_DIR}/logs"

CURRENT_USER="${SUDO_USER:-$USER}"
CURRENT_GROUP="$(id -gn "${CURRENT_USER}" 2>/dev/null || echo root)"

# ─── Create Directories ───
log_info "Creating application directories under ${BASE_DIR}..."
sudo mkdir -p "${MODEL_DIR}" "${INDEX_DIR}" "${CACHE_DIR}" "${STATE_DIR}" "${LOG_DIR}"

# ─── Set Ownership ───
log_info "Setting ownership to ${CURRENT_USER}:${CURRENT_GROUP}..."
sudo chown -R "${CURRENT_USER}:${CURRENT_GROUP}" "${BASE_DIR}"

# ─── Set Permissions ───
sudo chmod 755 "${BASE_DIR}"
sudo chmod 700 "${STATE_DIR}"
sudo chmod 755 "${MODEL_DIR}" "${INDEX_DIR}" "${CACHE_DIR}" "${LOG_DIR}"

# ─── Verify Python 3.13 ───
if command -v python3.13 &>/dev/null; then
    PYTHON_VERSION=$(python3.13 --version 2>&1)
    log_info "Python found: ${PYTHON_VERSION}"
else
    log_warn "python3.13 not found. Install with: sudo zypper install -y python313"
fi

# ─── Verify uv ───
if command -v uv &>/dev/null; then
    UV_VERSION=$(uv --version 2>&1 | head -1)
    log_info "uv found: ${UV_VERSION}"
else
    log_warn "uv not found. Install with: curl -LsSf https://astral.sh/uv/install.sh | sh"
fi

# ─── Verify Container Engine ───
if command -v podman &>/dev/null; then
    PODMAN_VERSION=$(podman --version 2>&1)
    log_info "Podman found: ${PODMAN_VERSION}"
elif command -v docker &>/dev/null; then
    DOCKER_VERSION=$(docker --version 2>&1)
    log_info "Docker found: ${DOCKER_VERSION}"
else
    log_warn "No container engine found. Install Podman: sudo zypper install -y podman"
fi

# ─── Summary ───
echo ""
log_info "Directory structure:"
echo "  ${BASE_DIR}/"
echo "  ├── models/      (LLM GGUF models)"
echo "  ├── index/       (RAG vector indices)"
echo "  ├── cache/docs/  (Crawled document cache)"
echo "  ├── state/       (Config and runtime state)"
echo "  └── logs/        (Application logs)"
echo ""
log_info "Ownership: ${CURRENT_USER}:${CURRENT_GROUP}"
log_info "Done. Run './scripts/download_models.sh' to fetch LLM models."
