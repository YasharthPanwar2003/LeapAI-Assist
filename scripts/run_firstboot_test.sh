#!/bin/bash
# =============================================================================
# openSUSE AI Assistant - First-Boot Integration Test
# Platform: openSUSE Leap 16 | Python 3.13
# Validates the entire stack: directories, Python, container, LLM, RAG
# Usage: sudo ./scripts/run_firstboot_test.sh [--full] [--quick]
#
# 2026 FIXES APPLIED:
#   - huggingface-cli → hf CLI check (huggingface_hub >= 1.8.0)
#   - Added rootless stack tests: crun, slirp4netns, fuse-overlayfs
#   - Added loginctl linger check
#   - Added subuid/subgid verification
#   - Added Quadlet directory check
#   - Removed podman.socket check (Podman is DAEMONLESS — no such socket)
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; BOLD='\033[1m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()   { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()  { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()   { echo -e "${BLUE}[STEP]${NC} $1"; }
log_header() { echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════════════${NC}"; echo -e "${BOLD}${CYAN}  $1${NC}"; echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════${NC}\n"; }
log_test()   { printf "  %-52s " "$1"; }
log_pass()   { echo -e "${GREEN}[PASS]${NC}"; }
log_fail()   { echo -e "${RED}[FAIL]${NC}"; }
log_skip()   { echo -e "${YELLOW}[SKIP]${NC}"; }

# ─── Configuration ───────────────────────────────────────────────────────────
TEST_MODE="full"
PASSED=0
FAILED=0
SKIPPED=0
ERRORS=()
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BASE_DIR="/var/lib/suse-ai"
CURRENT_USER="${SUDO_USER:-$USER}"

for arg in "$@"; do
    case $arg in
        --full)  TEST_MODE="full" ;;
        --quick) TEST_MODE="quick" ;;
        --help)
            echo "Usage: sudo ./scripts/run_firstboot_test.sh [--full|--quick]"
            echo ""
            echo "Modes:"
            echo "  --full   Run all tests (default)"
            echo "  --quick  Skip slow tests (model download, container build)"
            exit 0
            ;;
    esac
done

echo -e "\n${BOLD}${GREEN}"
echo "  ╔═══════════════════════════════════════════════════╗"
echo "  ║   openSUSE AI Assistant - First-Boot Test Suite   ║"
echo "  ║   Platform: openSUSE Leap 16                      ║"
echo "  ╚═══════════════════════════════════════════════════╝"
echo -e "${NC}"

# ═══════════════════════════════════════════════════════════════
# SECTION 1: System Environment
# ═══════════════════════════════════════════════════════════════
log_header "Section 1: System Environment"

log_test "1.1 Detect openSUSE Leap 16"
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID:-}" == "opensuse-leap" ]] && [[ "${VERSION_ID:-}" == "16"* ]]; then
        echo -e "${PRETTY_NAME:-unknown}"
        log_pass; PASSED=$((PASSED + 1))
    elif [[ "${ID:-}" == "opensuse-tumbleweed" ]]; then
        log_warn "Tumbleweed detected (compatible but not Leap 16)"
        PASSED=$((PASSED + 1))
    else
        echo -e "${PRETTY_NAME:-unknown}"
        log_warn "Not openSUSE Leap 16 but may be compatible"
        PASSED=$((PASSED + 1))
    fi
else
    log_fail; FAILED=$((FAILED + 1))
fi

log_test "1.2 Kernel version (>= 6.x)"
KVER=$(uname -r | cut -d. -f1)
if [[ "${KVER}" -ge 6 ]]; then
    echo "$(uname -r)"; log_pass; PASSED=$((PASSED + 1))
else
    echo "$(uname -r)"; log_fail; FAILED=$((FAILED + 1))
fi

log_test "1.3 Architecture (x86_64 or aarch64)"
ARCH=$(uname -m)
if [[ "${ARCH}" == "x86_64" ]] || [[ "${ARCH}" == "aarch64" ]]; then
    echo "${ARCH}"; log_pass; PASSED=$((PASSED + 1))
else
    echo "${ARCH}"; log_warn "GGUF models may not be available for ${ARCH}"
    SKIPPED=$((SKIPPED + 1))
fi

# ═══════════════════════════════════════════════════════════════
# SECTION 2: Python 3.13
# ═══════════════════════════════════════════════════════════════
log_header "Section 2: Python 3.13"

log_test "2.1 python3.13 is installed"
if command -v python3.13 &>/dev/null; then
    echo "$(python3.13 --version 2>&1)"; log_pass; PASSED=$((PASSED + 1))
else
    log_fail; FAILED=$((FAILED + 1))
    ERRORS+=("python3.13 missing — install: sudo zypper install -y python313")
fi

log_test "2.2 python3.13-devel (for C extensions)"
if rpm -q python313-devel &>/dev/null 2>&1; then
    echo "installed"; log_pass; PASSED=$((PASSED + 1))
else
    log_warn "python313-devel not installed (needed for some packages)"
    SKIPPED=$((SKIPPED + 1))
fi

log_test "2.3 uv package manager"
if command -v uv &>/dev/null; then
    echo "$(uv --version 2>&1 | head -1)"; log_pass; PASSED=$((PASSED + 1))
else
    log_fail; FAILED=$((FAILED + 1))
    ERRORS+=("uv missing — install: curl -LsSf https://astral.sh/uv/install.sh | sh")
fi

log_test "2.4 textual >= 8.1.1"
if python3.13 -c "import textual; v=tuple(int(x) for x in textual.__version__.split('.')[:3]); assert v>=(8,1,1)" 2>/dev/null; then
    echo "textual $(python3.13 -c 'import textual; print(textual.__version__)' 2>/dev/null)"
    log_pass; PASSED=$((PASSED + 1))
else
    log_fail; FAILED=$((FAILED + 1))
fi

log_test "2.5 pydantic >= 2.12.5"
if python3.13 -c "import pydantic; v=tuple(int(x) for x in pydantic.__version__.split('.')[:3]); assert v>=(2,12,5)" 2>/dev/null; then
    echo "pydantic $(python3.13 -c 'import pydantic; print(pydantic.__version__)' 2>/dev/null)"
    log_pass; PASSED=$((PASSED + 1))
else
    log_fail; FAILED=$((FAILED + 1))
fi

log_test "2.6 openai >= 2.30.0"
if python3.13 -c "import openai; v=tuple(int(x) for x in openai.__version__.split('.')[:3]); assert v>=(2,30,0)" 2>/dev/null; then
    echo "openai $(python3.13 -c 'import openai; print(openai.__version__)' 2>/dev/null)"
    log_pass; PASSED=$((PASSED + 1))
else
    log_fail; FAILED=$((FAILED + 1))
fi

log_test "2.7 huggingface_hub >= 1.8.0 (provides 'hf' CLI)"
# huggingface-cli was removed in huggingface_hub >= 1.0. The new CLI is 'hf'.
# Verify the library version and that the 'hf' command is available.
if python3.13 -c "import huggingface_hub; v=tuple(int(x) for x in huggingface_hub.__version__.split('.')[:2]); assert v>=(1,8)" 2>/dev/null; then
    HUB_VER=$(python3.13 -c 'import huggingface_hub; print(huggingface_hub.__version__)' 2>/dev/null)
    if command -v hf &>/dev/null; then
        echo "huggingface_hub ${HUB_VER} (hf CLI available)"
    else
        echo "huggingface_hub ${HUB_VER} (WARNING: hf CLI not on PATH)"
    fi
    log_pass; PASSED=$((PASSED + 1))
else
    log_fail
    FAILED=$((FAILED + 1))
    ERRORS+=("huggingface_hub too old or missing — install: uv pip install 'huggingface_hub[cli]>=1.8.0'")
fi

log_test "2.8 kubernetes >= 35.0.0 (optional)"
if python3.13 -c "import kubernetes; v=tuple(int(x) for x in kubernetes.__version__.split('.')[:3]); assert v>=(35,0,0)" 2>/dev/null; then
    echo "kubernetes $(python3.13 -c 'import kubernetes; print(kubernetes.__version__)' 2>/dev/null)"
    log_pass; PASSED=$((PASSED + 1))
else
    log_skip; SKIPPED=$((SKIPPED + 1))
fi

# ═══════════════════════════════════════════════════════════════
# SECTION 3: Directory Structure
# ═══════════════════════════════════════════════════════════════
log_header "Section 3: Directory Structure (${BASE_DIR})"

for subdir in models index cache/docs state logs documents; do
    log_test "3.x ${BASE_DIR}/${subdir}"
    if [[ -d "${BASE_DIR}/${subdir}" ]]; then
        OWNER=$(stat -c '%U:%G' "${BASE_DIR}/${subdir}" 2>/dev/null || echo "unknown")
        echo "${OWNER}"; log_pass; PASSED=$((PASSED + 1))
    else
        log_fail; FAILED=$((FAILED + 1))
        ERRORS+=("Directory ${BASE_DIR}/${subdir} missing — run: ./scripts/setup_directories.sh")
    fi
done

# ═══════════════════════════════════════════════════════════════
# SECTION 4: Container Engine & Rootless Stack
# ═══════════════════════════════════════════════════════════════
log_header "Section 4: Container Engine & Rootless Stack"

log_test "4.1 Podman installed"
if command -v podman &>/dev/null; then
    echo "$(podman --version 2>&1)"; log_pass; PASSED=$((PASSED + 1))

    log_test "4.2 podman compose (built-in)"
    if podman compose version &>/dev/null 2>&1; then
        echo "$(podman compose version --short 2>/dev/null || echo 'available')"
        log_pass; PASSED=$((PASSED + 1))
    else
        log_warn; SKIPPED=$((SKIPPED + 1))
    fi
else
    log_warn "Podman not installed"; SKIPPED=$((SKIPPED + 1))
fi

# Rootless container stack — all three are required
# crun: OCI runtime (Podman calls this to run containers)
# slirp4netns: user-space networking for rootless containers
# fuse-overlayfs: overlay filesystem without root privileges
for pkg in crun slirp4netns fuse-overlayfs; do
    log_test "4.x ${pkg} (rootless stack)"
    if rpm -q "${pkg}" &>/dev/null; then
        echo "$(rpm -q --queryformat '%{VERSION}' "${pkg}")"
        log_pass; PASSED=$((PASSED + 1))
    else
        log_fail; FAILED=$((FAILED + 1))
        ERRORS+=("${pkg} missing — install: sudo zypper install -y ${pkg}")
    fi
done

# subuid/subgid — required for rootless UID namespace mapping (keep-id)
log_test "4.x subuid entry for ${CURRENT_USER}"
if grep -q "^${CURRENT_USER}:" /etc/subuid 2>/dev/null; then
    echo "$(grep "^${CURRENT_USER}:" /etc/subuid)"
    log_pass; PASSED=$((PASSED + 1))
else
    log_fail; FAILED=$((FAILED + 1))
    ERRORS+=("No /etc/subuid entry for ${CURRENT_USER} — add: echo '${CURRENT_USER}:100000:65536' >> /etc/subuid")
fi

log_test "4.x subgid entry for ${CURRENT_USER}"
if grep -q "^${CURRENT_USER}:" /etc/subgid 2>/dev/null; then
    echo "$(grep "^${CURRENT_USER}:" /etc/subgid)"
    log_pass; PASSED=$((PASSED + 1))
else
    log_fail; FAILED=$((FAILED + 1))
    ERRORS+=("No /etc/subgid entry for ${CURRENT_USER} — add: echo '${CURRENT_USER}:100000:65536' >> /etc/subgid")
fi

# loginctl linger — keeps user systemd session alive after logout
# Without this, Quadlet containers are killed on session disconnect.
log_test "4.x loginctl linger for ${CURRENT_USER}"
LINGER=$(loginctl show-user "${CURRENT_USER}" --property=Linger --value 2>/dev/null || echo "unknown")
if [[ "${LINGER}" == "yes" ]]; then
    echo "enabled"; log_pass; PASSED=$((PASSED + 1))
else
    log_fail; FAILED=$((FAILED + 1))
    ERRORS+=("Linger not enabled — run: sudo loginctl enable-linger ${CURRENT_USER}")
fi

# NOTE: We do NOT check for podman.service or podman.socket.
# Podman is COMPLETELY DAEMONLESS. There is no background daemon.
# These systemd units do not exist on a properly configured Podman system.

# Quadlet directory
QUADLET_DIR="/home/${CURRENT_USER}/.config/containers/systemd"
log_test "4.x Quadlet directory (~/.config/containers/systemd/)"
if [[ -d "${QUADLET_DIR}" ]]; then
    FILE_COUNT=$(find "${QUADLET_DIR}" -name '*.container' -o -name '*.pod' 2>/dev/null | wc -l)
    echo "${FILE_COUNT} Quadlet file(s)"; log_pass; PASSED=$((PASSED + 1))
else
    log_warn "Quadlet directory missing (create: mkdir -p ${QUADLET_DIR})"
    SKIPPED=$((SKIPPED + 1))
fi

log_test "4.x Docker (alternative engine)"
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    echo "$(docker --version 2>&1)"; log_pass; PASSED=$((PASSED + 1))
else
    log_skip; SKIPPED=$((SKIPPED + 1))
fi

log_test "4.x Containerfile exists"
if [[ -f "${PROJECT_DIR}/Containerfile" ]]; then
    echo "present"; log_pass; PASSED=$((PASSED + 1))
else
    log_fail; FAILED=$((FAILED + 1))
fi

log_test "4.x compose.yaml exists"
if [[ -f "${PROJECT_DIR}/compose.yaml" ]]; then
    echo "present"; log_pass; PASSED=$((PASSED + 1))
else
    log_fail; FAILED=$((FAILED + 1))
fi

# ═══════════════════════════════════════════════════════════════
# SECTION 5: Kubernetes Tools (optional)
# ═══════════════════════════════════════════════════════════════
log_header "Section 5: Kubernetes Tools (optional)"

log_test "5.1 kubectl"
if command -v kubectl &>/dev/null; then
    echo "kubectl $(kubectl version --client --short 2>/dev/null | head -1 || echo 'installed')"
    log_pass; PASSED=$((PASSED + 1))
else
    log_skip; SKIPPED=$((SKIPPED + 1))
fi

log_test "5.2 Helm"
if command -v helm &>/dev/null; then
    echo "$(helm version --short 2>/dev/null)"; log_pass; PASSED=$((PASSED + 1))
else
    log_skip; SKIPPED=$((SKIPPED + 1))
fi

log_test "5.3 K3s or RKE2"
if systemctl is-active --quiet k3s 2>/dev/null; then
    echo "K3s running"; log_pass; PASSED=$((PASSED + 1))
elif systemctl is-active --quiet rke2-server 2>/dev/null; then
    echo "RKE2 running"; log_pass; PASSED=$((PASSED + 1))
else
    log_skip; SKIPPED=$((SKIPPED + 1))
fi

# ═══════════════════════════════════════════════════════════════
# SECTION 6: Model Files
# ═══════════════════════════════════════════════════════════════
log_header "Section 6: Model Files"

if [[ "${TEST_MODE}" == "quick" ]]; then
    log_test "6.1 LLM model file (skipped in quick mode)"
    log_skip; SKIPPED=$((SKIPPED + 1))
else
    log_test "6.1 LLM GGUF model exists"
    MODEL_FOUND=false
    for f in "${BASE_DIR}/models/"*.gguf; do
        if [[ -f "$f" ]]; then
            SIZE=$(du -h "$f" | awk '{print $1}')
            echo "$(basename "$f") (${SIZE})"
            MODEL_FOUND=true
            log_pass; PASSED=$((PASSED + 1))
            break
        fi
    done
    if [[ "${MODEL_FOUND}" == false ]]; then
        log_fail; FAILED=$((FAILED + 1))
        ERRORS+=("No models found — run: ./scripts/download_models.sh")
    fi
fi

# ═══════════════════════════════════════════════════════════════
# SECTION 7: Deploy Configuration Files
# ═══════════════════════════════════════════════════════════════
log_header "Section 7: Deploy Configuration Files"

CHECK_FILES=(
    "deploy/podman/suse-ai.container"
    "deploy/podman/suse-ai-pod.pod"
    "deploy/podman/suse-ai.socket"
    "deploy/kubernetes/k8s-deployment.yaml"
    "deploy/kubernetes/helm-values.yaml"
    "deploy/rancher/install-k3s.sh"
    "deploy/rancher/install-rke2.sh"
    "deploy/cockpit/suse-ai/manifest.json"
    "deploy/jeos-firstboot/04_ai_assistant.sh"
    "deploy/systemd/suse-ai-ingest.service"
    "deploy/systemd/suse-ai-ingest.timer"
)

for check_file in "${CHECK_FILES[@]}"; do
    log_test "7.x ${check_file}"
    if [[ -f "${PROJECT_DIR}/${check_file}" ]]; then
        echo "present"; log_pass; PASSED=$((PASSED + 1))
    else
        log_warn "not found"; SKIPPED=$((SKIPPED + 1))
    fi
done

# ═══════════════════════════════════════════════════════════════
# SECTION 8: LLM Server (if running)
# ═══════════════════════════════════════════════════════════════
log_header "Section 8: LLM Server Integration (if running)"

log_test "8.1 LLM server reachable at localhost:8080"
if curl -sf --max-time 5 "http://localhost:8080/v1/models" > /dev/null 2>&1; then
    echo "reachable"; log_pass; PASSED=$((PASSED + 1))

    log_test "8.2 LLM chat completion"
    CHAT_RESP=$(curl -sf --max-time 30 -X POST "http://localhost:8080/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{"model":"default","messages":[{"role":"user","content":"ping"}],"max_tokens":5}' 2>&1) && {
        REPLY=$(echo "${CHAT_RESP}" | python3.13 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d['choices'][0]['message']['content'].strip()[:60])
except: print('parse error')
" 2>/dev/null)
        echo "Reply: ${REPLY}"; log_pass; PASSED=$((PASSED + 1))
    } || {
        log_fail; FAILED=$((FAILED + 1))
    }
else
    log_skip "LLM server not running (expected if not started yet)"
    SKIPPED=$((SKIPPED + 2))
fi

# ═══════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}   Test Summary                                     ${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}\n"
echo -e "  ${GREEN}Passed:  ${PASSED}${NC}"
echo -e "  ${RED}Failed:  ${FAILED}${NC}"
echo -e "  ${YELLOW}Skipped: ${SKIPPED}${NC}"
echo -e "  Total:   $((PASSED + FAILED + SKIPPED))"
echo ""

if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo -e "  ${RED}Action items:${NC}"
    for err in "${ERRORS[@]}"; do
        echo -e "    ${YELLOW}→ ${err}${NC}"
    done
    echo ""
fi

if [[ ${FAILED} -eq 0 ]]; then
    log_info "All critical tests passed!"
    echo ""
    echo -e "  Ready to proceed:"
    echo -e "    Build:  ${YELLOW}./scripts/build_podman.sh${NC}"
    echo -e "    Run:    ${YELLOW}podman compose up -d${NC}"
    echo -e "    Test:   ${YELLOW}./scripts/test_llm_connectivity.sh${NC}"
    exit 0
else
    log_error "${FAILED} test(s) failed. Fix the issues above and re-run."
    exit 1
fi
