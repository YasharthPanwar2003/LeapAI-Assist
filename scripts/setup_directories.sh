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

BASE_DIR="/var/lib/suse-ai"
CURRENT_USER="${SUDO_USER:-$USER}"
CURRENT_GROUP="$(id -gn "${CURRENT_USER}" 2>/dev/null || echo root)"

log_info "Creating application directories under ${BASE_DIR}..."
mkdir -p \
    "${BASE_DIR}/models" \
    "${BASE_DIR}/index" \
    "${BASE_DIR}/cache/docs" \
    "${BASE_DIR}/state" \
    "${BASE_DIR}/logs" \
    "${BASE_DIR}/documents"

log_info "Setting ownership to ${CURRENT_USER}:${CURRENT_GROUP}..."
chown -R "${CURRENT_USER}:${CURRENT_GROUP}" "${BASE_DIR}"

chmod 755 "${BASE_DIR}"
chmod 700 "${BASE_DIR}/state"
chmod 755 "${BASE_DIR}/models" \
           "${BASE_DIR}/index" \
           "${BASE_DIR}/cache/docs" \
           "${BASE_DIR}/logs" \
           "${BASE_DIR}/documents"

# Verify Python 3.13
if command -v python3.13 &>/dev/null; then
    log_info "Python: $(python3.13 --version 2>&1)"
else
    log_warn "python3.13 not found. Install: sudo zypper install -y python313"
fi

# Verify uv
if command -v uv &>/dev/null; then
    log_info "uv: $(uv --version 2>&1 | head -1)"
else
    log_warn "uv not found. Install: curl -LsSf https://astral.sh/uv/install.sh | sh"
fi

# Verify hf CLI (replaces deprecated huggingface-cli)
if command -v hf &>/dev/null; then
    log_info "hf CLI: $(hf version 2>/dev/null | head -1 || echo 'available')"
else
    log_warn "'hf' CLI not found. Install: uv pip install 'huggingface_hub[cli]>=1.8.0'"
fi

# Verify container engine
if command -v podman &>/dev/null; then
    log_info "Podman: $(podman --version 2>&1)"
elif command -v docker &>/dev/null; then
    log_info "Docker: $(docker --version 2>&1)"
else
    log_warn "No container engine found. Install Podman: sudo zypper install -y podman"
fi

# Verify rootless stack
for pkg in crun slirp4netns fuse-overlayfs; do
    if rpm -q "${pkg}" &>/dev/null; then
        log_info "${pkg}: $(rpm -q --queryformat '%{VERSION}' "${pkg}")"
    else
        log_warn "${pkg} not installed — required for rootless containers"
        log_warn "  Install: sudo zypper install -y ${pkg}"
    fi
done

echo ""
log_info "Directory structure:"
echo "  ${BASE_DIR}/"
echo "  ├── models/      (LLM GGUF models)"
echo "  ├── index/       (RAG vector indices)"
echo "  ├── cache/docs/  (Crawled document cache)"
echo "  ├── documents/   (Source documents for ingestion)"
echo "  ├── state/       (Config and runtime state)"
echo "  └── logs/        (Application logs)"
echo ""
log_info "Ownership: ${CURRENT_USER}:${CURRENT_GROUP}"
echo ""
log_info "Next steps:"
echo "  1. Login to HF Hub: hf auth login"
echo "  2. Download models: ./scripts/download_models.sh"
echo "  3. Build image:     ./scripts/build_podman.sh"
