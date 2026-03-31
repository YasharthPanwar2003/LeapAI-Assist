#!/bin/bash
# =============================================================================
# openSUSE AI Assistant - Model Download Script
# Platform: openSUSE Leap 16 | Python 3.13
# Downloads quantized GGUF models from Hugging Face
# Usage: ./scripts/download_models.sh [--model-dir /path] [--all] [--small]
#
# 2026 FIXES APPLIED:
#   - huggingface-cli is REMOVED in huggingface_hub >= 1.0
#   - All 'huggingface-cli download' → 'hf download'
#   - All 'huggingface-cli login'    → 'hf auth login'
#   - Added 'hf auth whoami' pre-flight check
#   - huggingface_hub pinned to >= 1.8.0 in install instructions
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# ─── Configuration ───────────────────────────────────────────────────────────
MODEL_DIR="/var/lib/suse-ai/models"
DOWNLOAD_ALL=false
DOWNLOAD_SMALL=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Model Definitions ───────────────────────────────────────────────────────
DEFAULT_MODEL_REPO="LibrAI/LFM2.5-1.2B-Instruct-GGUF"
DEFAULT_MODEL_FILE="LFM2.5-1.2B-Instruct-Q4_K_M.gguf"
DEFAULT_MODEL_URL="https://huggingface.co/${DEFAULT_MODEL_REPO}/resolve/main/${DEFAULT_MODEL_FILE}"

LARGE_MODEL_REPO="bartowski/Llama-3.2-3B-Instruct-GGUF"
LARGE_MODEL_FILE="Llama-3.2-3B-Instruct-Q4_K_M.gguf"
LARGE_MODEL_URL="https://huggingface.co/${LARGE_MODEL_REPO}/resolve/main/${LARGE_MODEL_FILE}"

EMBED_MODEL_REPO="jinaai/jina-embeddings-v5-text-nano"
EMBED_MODEL_FILE="jina-embeddings-v5-text-nano-q4_k_m.gguf"
EMBED_MODEL_URL="https://huggingface.co/${EMBED_MODEL_REPO}/resolve/main/${EMBED_MODEL_FILE}"

# ─── Parse Arguments ─────────────────────────────────────────────────────────
for arg in "$@"; do
    case $arg in
        --model-dir) shift; MODEL_DIR="${1:-/var/lib/suse-ai/models}" ;;
        --all)       DOWNLOAD_ALL=true ;;
        --small)     DOWNLOAD_SMALL=true ;;
        --help)
            echo "Usage: ./scripts/download_models.sh [--model-dir /path] [--all] [--small]"
            echo ""
            echo "Options:"
            echo "  --model-dir DIR  Download to directory (default: /var/lib/suse-ai/models)"
            echo "  --all            Download all models (default + large + embedding)"
            echo "  --small          Download only the smallest model"
            echo ""
            echo "Requirements:"
            echo "  uv pip install 'huggingface_hub[cli]>=1.8.0'"
            echo "  hf auth login"
            exit 0
            ;;
    esac
done

# ─── Pre-flight: Detect hf CLI ───────────────────────────────────────────────
# 'huggingface-cli' was permanently removed in huggingface_hub 1.0 (2025).
# The replacement is the 'hf' command. The old name will produce:
#   bash: huggingface-cli: command not found
# Install: uv pip install 'huggingface_hub[cli]>=1.8.0'
# Login:   hf auth login
log_step "Pre-flight checks"

HF_CLI=""
if command -v hf &>/dev/null; then
    HF_CLI="hf"
    log_info "hf CLI found: $(hf version 2>/dev/null | head -1 || echo 'ok')"
elif python3.13 -c "from huggingface_hub.cli import app" &>/dev/null 2>&1; then
    HF_CLI="python3.13 -m huggingface_hub"
    log_info "hf available via python3.13 -m huggingface_hub"
else
    log_warn "'hf' CLI not found."
    log_warn "Install: uv pip install 'huggingface_hub[cli]>=1.8.0'"
    log_warn "Login:   hf auth login"
fi

# Check authentication — required for gated/rate-limited repos
if [[ -n "${HF_CLI}" ]]; then
    HF_USER=$(${HF_CLI} auth whoami 2>/dev/null | grep -oP '(?<=Logged in as: ).*' || echo "")
    if [[ -n "${HF_USER}" ]]; then
        log_info "Authenticated as: ${HF_USER}"
    else
        log_warn "Not authenticated with Hugging Face."
        log_warn "Some models require auth. Run: hf auth login"
    fi
fi

# Check for curl/wget fallback
if command -v curl &>/dev/null; then
    DOWNLOAD_CMD="curl -L -f -o"
    log_info "curl fallback available"
elif command -v wget &>/dev/null; then
    DOWNLOAD_CMD="wget -O"
    log_info "wget fallback available"
else
    log_error "Neither hf CLI, curl, nor wget found. Cannot download models."
    log_error "Install: sudo zypper install -y curl"
    exit 1
fi

# Create model directory
mkdir -p "${MODEL_DIR}"
log_info "Model directory: ${MODEL_DIR}"

# Check disk space (need ~2 GB for default model)
AVAILABLE_GB=$(df -BG "${MODEL_DIR}" | awk 'NR==2 {print $4}' | tr -d 'G')
if [[ "${AVAILABLE_GB}" -lt 2 ]]; then
    log_warn "Low disk space: ${AVAILABLE_GB}GB available. Need at least 2 GB."
fi

# ─── Download Function ───────────────────────────────────────────────────────
download_model() {
    local name="$1"
    local url="$2"
    local output="$3"
    local repo="$4"
    local filename="$5"

    if [[ -f "${output}" ]]; then
        local sz; sz=$(du -m "${output}" | awk '{print $1}')
        log_info "${name} already exists (${sz} MB). Skipping."
        return 0
    fi

    log_step "Downloading ${name}..."
    log_info "Repo: ${repo}"
    log_info "File: ${filename}"
    log_info "Destination: ${output}"

    local start; start=$(date +%s)

    # Preferred path: hf download (supports resume, progress bar, auth)
    # Usage: hf download <repo_id> <filename> --local-dir <dir>
    if [[ -n "${HF_CLI}" ]]; then
        log_info "Using hf download (resumable)..."
        if ${HF_CLI} download "${repo}" "${filename}" \
               --local-dir "${MODEL_DIR}" \
               --local-dir-use-symlinks False 2>/dev/null; then
            local end; end=$(date +%s)
            local sz; sz=$(du -m "${output}" | awk '{print $1}')
            log_info "Downloaded ${sz} MB in $((end - start))s"
            return 0
        fi
        log_warn "hf download failed — falling back to curl..."
    fi

    # Fallback: direct URL download via curl or wget
    ${DOWNLOAD_CMD} "${output}.tmp" "${url}" && mv "${output}.tmp" "${output}"

    local end; end=$(date +%s)
    if [[ -f "${output}" ]]; then
        local sz; sz=$(du -m "${output}" | awk '{print $1}')
        log_info "Downloaded ${sz} MB in $((end - start))s"
    else
        log_error "Download failed for ${name}"
        return 1
    fi
}

# ─── Download Default Model ──────────────────────────────────────────────────
echo ""
log_info "=== Default LLM Model: LFM 2.5 1.2B Q4_K_M ==="
download_model \
    "LFM 2.5 (1.2B Q4_K_M)" \
    "${DEFAULT_MODEL_URL}" \
    "${MODEL_DIR}/${DEFAULT_MODEL_FILE}" \
    "${DEFAULT_MODEL_REPO}" \
    "${DEFAULT_MODEL_FILE}"

# ─── Download Large Model (optional) ────────────────────────────────────────
if [[ "${DOWNLOAD_ALL}" == true ]] && [[ "${DOWNLOAD_SMALL}" != true ]]; then
    echo ""
    log_info "=== Large LLM Model: Llama 3.2 3B Q4_K_M ==="
    download_model \
        "Llama 3.2 (3B Q4_K_M)" \
        "${LARGE_MODEL_URL}" \
        "${MODEL_DIR}/${LARGE_MODEL_FILE}" \
        "${LARGE_MODEL_REPO}" \
        "${LARGE_MODEL_FILE}"
fi

# ─── Download Embedding Model (optional) ────────────────────────────────────
if [[ "${DOWNLOAD_ALL}" == true ]]; then
    echo ""
    log_info "=== Embedding Model: Jina v5 nano Q4 ==="
    download_model \
        "Jina Embeddings v5 (nano Q4)" \
        "${EMBED_MODEL_URL}" \
        "${MODEL_DIR}/${EMBED_MODEL_FILE}" \
        "${EMBED_MODEL_REPO}" \
        "${EMBED_MODEL_FILE}"
fi

# ─── Verify ──────────────────────────────────────────────────────────────────
echo ""
log_step "Verifying downloads..."
echo ""
echo "  Models in ${MODEL_DIR}:"
echo "  ─────────────────────────────────────────────────────"
FOUND=0
for f in "${MODEL_DIR}"/*.gguf; do
    if [[ -f "$f" ]]; then
        SIZE=$(du -h "$f" | awk '{print $1}')
        NAME=$(basename "$f")
        echo "  ${SIZE}    ${NAME}"
        FOUND=$((FOUND + 1))
    fi
done
if [[ $FOUND -eq 0 ]]; then
    log_warn "No .gguf files found in ${MODEL_DIR}"
fi
echo "  ─────────────────────────────────────────────────────"

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
log_info "Download complete! (${FOUND} model(s))"
echo ""
echo "  Next steps:"
echo "    1. Build image: ${YELLOW}./scripts/build_podman.sh${NC}"
echo "    2. Test LLM:    ${YELLOW}./scripts/test_llm_connectivity.sh${NC}"
echo "    3. Run:         ${YELLOW}podman compose up -d${NC}"
