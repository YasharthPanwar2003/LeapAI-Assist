#!/bin/bash
# =============================================================================
# openSUSE AI Assistant - Model Download Script
# Platform: openSUSE Leap 16 | Python 3.13
# Downloads quantized GGUF models from Hugging Face
# Usage: ./scripts/download_models.sh [--model-dir /path] [--all] [--small]
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# ─── Configuration ───
MODEL_DIR="/var/lib/suse-ai/models"
DOWNLOAD_ALL=false
DOWNLOAD_SMALL=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ─── Model Definitions ───
# Default: LFM 2.5 (Llama-based, good balance of speed/quality)
DEFAULT_MODEL_REPO="LibrAI/LFM2.5-1.2B-Instruct-GGUF"
DEFAULT_MODEL_FILE="LFM2.5-1.2B-Instruct-Q4_K_M.gguf"
DEFAULT_MODEL_URL="https://huggingface.co/${DEFAULT_MODEL_REPO}/resolve/main/${DEFAULT_MODEL_FILE}"

# Optional: Larger model for better quality
LARGE_MODEL_REPO="bartowski/Llama-3.2-3B-Instruct-GGUF"
LARGE_MODEL_FILE="Llama-3.2-3B-Instruct-Q4_K_M.gguf"
LARGE_MODEL_URL="https://huggingface.co/${LARGE_MODEL_REPO}/resolve/main/${LARGE_MODEL_FILE}"

# Optional: Embedding model for RAG
EMBED_MODEL_REPO="jinaai/jina-embeddings-v5-text-nano"
EMBED_MODEL_FILE="jina-embeddings-v5-text-nano-q4_k_m.gguf"
EMBED_MODEL_URL="https://huggingface.co/${EMBED_MODEL_REPO}/resolve/main/${EMBED_MODEL_FILE}"

# ─── Parse Arguments ───
for arg in "$@"; do
    case $arg in
        --model-dir) shift; MODEL_DIR="${1:-/var/lib/suse-ai/models}" ;;
        --all) DOWNLOAD_ALL=true ;;
        --small) DOWNLOAD_SMALL=true ;;
        --help)
            echo "Usage: ./scripts/download_models.sh [--model-dir /path] [--all] [--small]"
            echo ""
            echo "Downloads LLM models for the openSUSE AI Assistant."
            echo ""
            echo "Options:"
            echo "  --model-dir DIR  Download to directory (default: /var/lib/suse-ai/models)"
            echo "  --all            Download all models (default + large + embedding)"
            echo "  --small          Download only the smallest model"
            exit 0
            ;;
    esac
done

# ─── Pre-flight Checks ───
log_step "Pre-flight checks"

# Check for download tools
if command -v curl &>/dev/null; then
    DOWNLOAD_CMD="curl -L -f -o"
    log_info "Using curl for downloads"
elif command -v wget &>/dev/null; then
    DOWNLOAD_CMD="wget -O"
    log_info "Using wget for downloads"
else
    log_error "Neither curl nor wget found. Install: sudo zypper install -y curl"
    exit 1
fi

# Check for huggingface-cli
HF_CLI=""
if command -v huggingface-cli &>/dev/null; then
    HF_CLI="huggingface-cli"
    log_info "huggingface-cli found"
elif python3.13 -m huggingface_hub.cli &>/dev/null 2>&1; then
    HF_CLI="python3.13 -m huggingface_hub.cli"
    log_info "huggingface-cli available via python3.13 -m huggingface_hub.cli"
else
    log_warn "huggingface-cli not found. Install: uv pip install huggingface_hub"
fi

# Create model directory
mkdir -p "${MODEL_DIR}"
log_info "Model directory: ${MODEL_DIR}"

# Check disk space (need ~2GB for default model)
AVAILABLE_GB=$(df -BG "${MODEL_DIR}" | awk 'NR==2 {print $4}' | tr -d 'G')
if [[ "${AVAILABLE_GB}" -lt 2 ]]; then
    log_warn "Low disk space: ${AVAILABLE_GB}GB available. Need at least 2GB."
fi

# ─── Download Function ───
download_model() {
    local name="$1"
    local url="$2"
    local output="$3"
    local expected_size_mb="${4:-0}"

    if [[ -f "${output}" ]]; then
        ACTUAL_SIZE=$(du -m "${output}" | awk '{print $1}')
        log_info "${name} already exists (${ACTUAL_SIZE}MB). Skipping."
        return 0
    fi

    log_step "Downloading ${name}..."
    log_info "URL: ${url}"
    log_info "Output: ${output}"

    DL_START=$(date +%s)

    # Try huggingface-cli first (resumable)
    if [[ -n "${HF_CLI}" ]]; then
        log_info "Using huggingface-cli (resumable)..."
        # Parse repo and file from URL
        local repo=$(echo "${url}" | sed 's|https://huggingface.co/\(.*\)/resolve/main/.*|\1|')
        local file=$(basename "${url}")
        if ${HF_CLI} download "${repo}" "${file}" --local-dir "${MODEL_DIR}" --local-dir-use-symlinks False 2>/dev/null; then
            DL_END=$(date +%s)
            log_info "Downloaded in $((DL_END - DL_START))s"
            return 0
        fi
        log_warn "huggingface-cli failed, falling back to curl..."
    fi

    # Fallback to curl/wget
    ${DOWNLOAD_CMD} "${output}.tmp" "${url}" && mv "${output}.tmp" "${output}"

    DL_END=$(date +%s)
    if [[ -f "${output}" ]]; then
        ACTUAL_SIZE=$(du -m "${output}" | awk '{print $1}')
        log_info "Downloaded ${ACTUAL_SIZE}MB in $((DL_END - DL_START))s"
    else
        log_error "Download failed for ${name}"
        return 1
    fi
}

# ─── Download Default Model ───
echo ""
log_info "=== Downloading Default LLM Model ==="
download_model "LFM 2.5 (1.2B Q4_K_M)" "${DEFAULT_MODEL_URL}" "${MODEL_DIR}/${DEFAULT_MODEL_FILE}" 700

# ─── Download Large Model (optional) ───
if [[ "${DOWNLOAD_ALL}" == true ]] && [[ "${DOWNLOAD_SMALL}" != true ]]; then
    echo ""
    log_info "=== Downloading Large LLM Model ==="
    download_model "Llama 3.2 (3B Q4_K_M)" "${LARGE_MODEL_URL}" "${MODEL_DIR}/${LARGE_MODEL_FILE}" 1800
fi

# ─── Download Embedding Model (optional) ───
if [[ "${DOWNLOAD_ALL}" == true ]]; then
    echo ""
    log_info "=== Downloading Embedding Model ==="
    download_model "Jina Embeddings v5 (nano Q4)" "${EMBED_MODEL_URL}" "${MODEL_DIR}/${EMBED_MODEL_FILE}" 200
fi

# ─── Verify ───
echo ""
log_step "Verifying downloads..."
echo ""
echo "  Models in ${MODEL_DIR}:"
echo "  ─────────────────────────────────────────────"
for f in "${MODEL_DIR}"/*.gguf; do
    if [[ -f "$f" ]]; then
        SIZE=$(du -h "$f" | awk '{print $1}')
        NAME=$(basename "$f")
        echo "  ${SIZE}  ${NAME}"
    fi
done
echo "  ─────────────────────────────────────────────"

# ─── Summary ───
echo ""
log_info "Download complete!"
echo ""
echo "  Next steps:"
echo "    1. Build image:  ${YELLOW}./scripts/build_podman.sh${NC}"
echo "    2. Test LLM:     ${YELLOW}./scripts/test_llm_connectivity.sh${NC}"
echo "    3. Run:          ${YELLOW}podman compose up -d${NC}"
