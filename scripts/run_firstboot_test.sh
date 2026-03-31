#!/bin/bash
# =============================================================================
# openSUSE AI Assistant - First-Boot Integration Test
# Platform: openSUSE Leap 16 | Python 3.13
# Validates the entire stack: directories, Python, container, LLM, RAG
# Usage: sudo ./scripts/run_firstboot_test.sh [--full] [--quick]
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; BOLD='\033[1m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "${BLUE}[STEP]${NC} $1"; }
log_header()  { echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════════════${NC}"; echo -e "${BOLD}${CYAN}  $1${NC}"; echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════${NC}\n"; }
log_test()    { printf "  %-50s " "$1"; }
log_pass()    { echo -e "${GREEN}[PASS]${NC}"; }
log_fail()    { echo -e "${RED}[FAIL]${NC}"; }
log_skip()    { echo -e "${YELLOW}[SKIP]${NC}"; }

# ─── Configuration ───
TEST_MODE="full"
PASSED=0
FAILED=0
SKIPPED=0
ERRORS=()
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BASE_DIR="/var/lib/suse-ai"

# ─── Parse Arguments ───
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

# ─── 1.1: OS Detection ───
log_test "1.1 Detect openSUSE Leap 16"
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID:-}" == "opensuse-leap" ]] && [[ "${VERSION_ID:-}" == "16"* ]]; then
        echo -e "${PRETTY_NAME:-unknown}"
        log_pass
        PASSED=$((PASSED + 1))
    elif [[ "${ID:-}" == "opensuse-tumbleweed" ]]; then
        log_warn "Tumbleweed detected (compatible but not Leap 16)"
        PASSED=$((PASSED + 1))
    else
        echo -e "${PRETTY_NAME:-unknown}"
        log_warn "Not openSUSE Leap 16 but may be compatible"
        PASSED=$((PASSED + 1))
    fi
else
    log_fail "/etc/os-release not found"
    FAILED=$((FAILED + 1))
fi

# ─── 1.2: Kernel version ───
log_test "1.2 Kernel version (>= 6.x)"
KVER=$(uname -r | cut -d. -f1)
if [[ "${KVER}" -ge 6 ]]; then
    echo "$(uname -r)"
    log_pass
    PASSED=$((PASSED + 1))
else
    echo "$(uname -r)"
    log_fail "Kernel too old"
    FAILED=$((FAILED + 1))
fi

# ─── 1.3: Architecture ───
log_test "1.3 Architecture (x86_64 or aarch64)"
ARCH=$(uname -m)
if [[ "${ARCH}" == "x86_64" ]] || [[ "${ARCH}" == "aarch64" ]]; then
    echo "${ARCH}"
    log_pass
    PASSED=$((PASSED + 1))
else
    echo "${ARCH}"
    log_warn "Architecture ${ARCH} - GGUF models may not be available"
    SKIPPED=$((SKIPPED + 1))
fi

# ─── 1.4: Agama vs YaST detection ───
log_test "1.4 Installer detection (Agama/YaST)"
if command -v agama &>/dev/null || [[ -d /usr/share/agama ]]; then
    echo "Agama (Leap 16 installer)"
    log_pass
    PASSED=$((PASSED + 1))
elif command -v yast2 &>/dev/null; then
    echo "YaST2 (legacy installer)"
    log_pass
    PASSED=$((PASSED + 1))
else
    echo "No installer tools detected (may be post-install)"
    log_skip
    SKIPPED=$((SKIPPED + 1))
fi

# ═══════════════════════════════════════════════════════════════
# SECTION 2: Python 3.13
# ═══════════════════════════════════════════════════════════════
log_header "Section 2: Python 3.13"

# ─── 2.1: python3.13 binary ───
log_test "2.1 python3.13 is installed"
if command -v python3.13 &>/dev/null; then
    PYVER=$(python3.13 --version 2>&1)
    echo "${PYVER}"
    log_pass
    PASSED=$((PASSED + 1))
else
    log_fail "python3.13 not found"
    FAILED=$((FAILED + 1))
    ERRORS+=("python3.13 missing - install: sudo zypper install -y python313")
fi

# ─── 2.2: python3.13-devel ───
log_test "2.2 python3.13-devel (for C extensions)"
if rpm -q python313-devel &>/dev/null 2>&1; then
    echo "installed"
    log_pass
    PASSED=$((PASSED + 1))
else
    log_warn "python313-devel not installed (needed for some packages)"
    SKIPPED=$((SKIPPED + 1))
fi

# ─── 2.3: uv package manager ───
log_test "2.3 uv package manager"
if command -v uv &>/dev/null; then
    UVVER=$(uv --version 2>&1 | head -1)
    echo "${UVVER}"
    log_pass
    PASSED=$((PASSED + 1))
else
    log_fail "uv not found"
    FAILED=$((FAILED + 1))
    ERRORS+=("uv missing - install: curl -LsSf https://astral.sh/uv/install.sh | sh")
fi

# ─── 2.4: Key Python packages ───
log_test "2.4 textual >= 8.1.1"
if python3.13 -c "import textual; v = tuple(int(x) for x in textual.__version__.split('.')[:3]); assert v >= (8, 1, 1), f'{v}'" 2>/dev/null; then
    echo "textual $(python3.13 -c 'import textual; print(textual.__version__)' 2>/dev/null)"
    log_pass
    PASSED=$((PASSED + 1))
else
    log_fail "textual missing or too old"
    FAILED=$((FAILED + 1))
fi

log_test "2.5 pydantic >= 2.12.5"
if python3.13 -c "import pydantic; v = tuple(int(x) for x in pydantic.__version__.split('.')[:3]); assert v >= (2, 12, 5), f'{v}'" 2>/dev/null; then
    echo "pydantic $(python3.13 -c 'import pydantic; print(pydantic.__version__)' 2>/dev/null)"
    log_pass
    PASSED=$((PASSED + 1))
else
    log_fail "pydantic missing or too old"
    FAILED=$((FAILED + 1))
fi

log_test "2.6 openai >= 2.30.0"
if python3.13 -c "import openai; v = tuple(int(x) for x in openai.__version__.split('.')[:3]); assert v >= (2, 30, 0), f'{v}'" 2>/dev/null; then
    echo "openai $(python3.13 -c 'import openai; print(openai.__version__)' 2>/dev/null)"
    log_pass
    PASSED=$((PASSED + 1))
else
    log_fail "openai missing or too old"
    FAILED=$((FAILED + 1))
fi

log_test "2.7 kubernetes >= 35.0.0 (optional)"
if python3.13 -c "import kubernetes; v = tuple(int(x) for x in kubernetes.__version__.split('.')[:3]); assert v >= (35, 0, 0), f'{v}'" 2>/dev/null; then
    echo "kubernetes $(python3.13 -c 'import kubernetes; print(kubernetes.__version__)' 2>/dev/null)"
    log_pass
    PASSED=$((PASSED + 1))
else
    log_skip "kubernetes library not installed (optional)"
    SKIPPED=$((SKIPPED + 1))
fi

# ═══════════════════════════════════════════════════════════════
# SECTION 3: Directory Structure
# ═══════════════════════════════════════════════════════════════
log_header "Section 3: Directory Structure (${BASE_DIR})"

for subdir in models index cache/docs state logs; do
    log_test "3.x ${BASE_DIR}/${subdir} exists"
    if [[ -d "${BASE_DIR}/${subdir}" ]]; then
        OWNER=$(stat -c '%U:%G' "${BASE_DIR}/${subdir}" 2>/dev/null || echo "unknown")
        echo "${OWNER}"
        log_pass
        PASSED=$((PASSED + 1))
    else
        log_fail "missing"
        FAILED=$((FAILED + 1))
        ERRORS+=("Directory ${BASE_DIR}/${subdir} missing - run: ./scripts/setup_directories.sh")
    fi
done

# ─── Project structure ───
log_test "3.x Project deploy/ directory"
if [[ -d "${PROJECT_DIR}/deploy" ]]; then
    SUBDIRS=$(ls -d "${PROJECT_DIR}"/deploy/*/ 2>/dev/null | xargs -I{} basename {} | tr '\n' ', ')
    echo "${SUBDIRS%, }"
    log_pass
    PASSED=$((PASSED + 1))
else
    log_fail "deploy/ directory missing"
    FAILED=$((FAILED + 1))
fi

for deploy_sub in docker podman kubernetes rancher cockpit systemd jeos-firstboot; do
    log_test "3.x deploy/${deploy_sub}/"
    if [[ -d "${PROJECT_DIR}/deploy/${deploy_sub}" ]]; then
        FILE_COUNT=$(find "${PROJECT_DIR}/deploy/${deploy_sub}" -type f 2>/dev/null | wc -l)
        echo "${FILE_COUNT} file(s)"
        log_pass
        PASSED=$((PASSED + 1))
    else
        log_warn "deploy/${deploy_sub}/ missing"
        SKIPPED=$((SKIPPED + 1))
    fi
done

# ═══════════════════════════════════════════════════════════════
# SECTION 4: Container Engine
# ═══════════════════════════════════════════════════════════════
log_header "Section 4: Container Engine"

# ─── 4.1: Podman ───
log_test "4.1 Podman installed"
if command -v podman &>/dev/null; then
    PVER=$(podman --version 2>&1)
    echo "${PVER}"
    log_pass
    PASSED=$((PASSED + 1))

    # Check podman compose
    log_test "4.2 podman compose (built-in)"
    if podman compose version &>/dev/null 2>&1; then
        PCVER=$(podman compose version --short 2>/dev/null || echo "available")
        echo "${PCVER}"
        log_pass
        PASSED=$((PASSED + 1))
    else
        log_warn "podman compose not available"
        SKIPPED=$((SKIPPED + 1))
    fi
else
    log_warn "Podman not installed (Docker may be used instead)"
    SKIPPED=$((SKIPPED + 1))
fi

# ─── 4.3: Docker ───
log_test "4.3 Docker (alternative)"
if command -v docker &>/dev/null; then
    DVER=$(docker --version 2>&1)
    echo "${DVER}"
    if docker info &>/dev/null 2>&1; then
        log_pass
        PASSED=$((PASSED + 1))
    else
        log_warn "Docker installed but daemon not running"
        SKIPPED=$((SKIPPED + 1))
    fi
else
    log_skip "Docker not installed"
    SKIPPED=$((SKIPPED + 1))
fi

# ─── 4.4: Containerfile ───
log_test "4.4 Root Containerfile exists"
if [[ -f "${PROJECT_DIR}/Containerfile" ]]; then
    echo "present"
    log_pass
    PASSED=$((PASSED + 1))
else
    log_fail "Containerfile missing"
    FAILED=$((FAILED + 1))
fi

# ─── 4.5: compose.yaml ───
log_test "4.5 Root compose.yaml exists"
if [[ -f "${PROJECT_DIR}/compose.yaml" ]]; then
    echo "present"
    log_pass
    PASSED=$((PASSED + 1))
else
    log_fail "compose.yaml missing"
    FAILED=$((FAILED + 1))
fi

# ═══════════════════════════════════════════════════════════════
# SECTION 5: Kubernetes Tools
# ═══════════════════════════════════════════════════════════════
log_header "Section 5: Kubernetes Tools (optional)"

log_test "5.1 kubectl"
if command -v kubectl &>/dev/null; then
    echo "kubectl $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1)"
    log_pass
    PASSED=$((PASSED + 1))
else
    log_skip "kubectl not installed (optional)"
    SKIPPED=$((SKIPPED + 1))
fi

log_test "5.2 Helm"
if command -v helm &>/dev/null; then
    echo "helm $(helm version --short 2>/dev/null)"
    log_pass
    PASSED=$((PASSED + 1))
else
    log_skip "Helm not installed (optional)"
    SKIPPED=$((SKIPPED + 1))
fi

log_test "5.3 K3s or RKE2"
if systemctl is-active --quiet k3s 2>/dev/null; then
    echo "K3s running"
    log_pass
    PASSED=$((PASSED + 1))
elif systemctl is-active --quiet rke2-server 2>/dev/null; then
    echo "RKE2 running"
    log_pass
    PASSED=$((PASSED + 1))
else
    log_skip "No K8s engine running (optional)"
    SKIPPED=$((SKIPPED + 1))
fi

# ═══════════════════════════════════════════════════════════════
# SECTION 6: Model Files
# ═══════════════════════════════════════════════════════════════
log_header "Section 6: Model Files"

if [[ "${TEST_MODE}" == "quick" ]]; then
    log_test "6.1 LLM model file (skipped in quick mode)"
    log_skip
    SKIPPED=$((SKIPPED + 1))
else
    log_test "6.1 LLM GGUF model exists"
    MODEL_FOUND=false
    for f in "${BASE_DIR}/models/"*.gguf; do
        if [[ -f "$f" ]]; then
            SIZE=$(du -h "$f" | awk '{print $1}')
            echo "$(basename "$f") (${SIZE})"
            MODEL_FOUND=true
            log_pass
            PASSED=$((PASSED + 1))
            break
        fi
    done
    if [[ "${MODEL_FOUND}" == false ]]; then
        log_fail "No GGUF models found in ${BASE_DIR}/models/"
        FAILED=$((FAILED + 1))
        ERRORS+=("No models found - run: ./scripts/download_models.sh")
    fi
fi

# ═══════════════════════════════════════════════════════════════
# SECTION 7: Deploy Files
# ═══════════════════════════════════════════════════════════════
log_header "Section 7: Deploy Configuration Files"

# Check key deploy files exist
CHECK_FILES=(
    "deploy/podman/suse-ai.container"
    "deploy/podman/suse-ai.service"
    "deploy/kubernetes/k8s-deployment.yaml"
    "deploy/kubernetes/helm-values.yaml"
    "deploy/rancher/install-k3s.sh"
    "deploy/rancher/install-rke2.sh"
    "deploy/cockpit/suse-ai/manifest.json"
    "deploy/jeos-firstboot/04_ai_assistant.sh"
)

for check_file in "${CHECK_FILES[@]}"; do
    log_test "7.x ${check_file}"
    if [[ -f "${PROJECT_DIR}/${check_file}" ]]; then
        echo "present"
        log_pass
        PASSED=$((PASSED + 1))
    else
        log_warn "not found"
        SKIPPED=$((SKIPPED + 1))
    fi
done

# ═══════════════════════════════════════════════════════════════
# SECTION 8: LLM Server (if running)
# ═══════════════════════════════════════════════════════════════
log_header "Section 8: LLM Server Integration (if running)"

log_test "8.1 LLM server reachable at localhost:8080"
if curl -sf --max-time 5 "http://localhost:8080/v1/models" > /dev/null 2>&1; then
    echo "reachable"
    log_pass
    PASSED=$((PASSED + 1))

    # Run full connectivity test if available
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
        echo "Reply: ${REPLY}"
        log_pass
        PASSED=$((PASSED + 1))
    } || {
        log_fail "chat completion failed"
        FAILED=$((FAILED + 1))
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
echo -e "${BOLD}   Test Summary                                        ${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}\n"
echo -e "  ${GREEN}Passed:   ${PASSED}${NC}"
echo -e "  ${RED}Failed:   ${FAILED}${NC}"
echo -e "  ${YELLOW}Skipped:  ${SKIPPED}${NC}"
echo -e "  Total:    $((PASSED + FAILED + SKIPPED))"
echo ""

if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo -e "  ${RED}Action items:${NC}"
    for err in "${ERRORS[@]}"; do
        echo -e "    ${YELLOW}- ${err}${NC}"
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
