#!/bin/bash
# =============================================================================
# openSUSE AI Assistant - LLM Connectivity Test
# Platform: openSUSE Leap 16 | Python 3.13
# Tests that the LLM server is running and responding correctly
# Usage: ./scripts/test_llm_connectivity.sh [--host localhost] [--port 8080]
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }
log_pass()  { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail()  { echo -e "${RED}[FAIL]${NC} $1"; }

# ─── Configuration ───
LLM_HOST="${LLM_HOST:-localhost}"
LLM_PORT="${LLM_PORT:-8080}"
LLM_BASE_URL="http://${LLM_HOST}:${LLM_PORT}/v1"
PASSED=0
FAILED=0
WARNINGS=0

# ─── Parse Arguments ───
for arg in "$@"; do
    case $arg in
        --host) shift; LLM_HOST="${1:-localhost}" ;;
        --port) shift; LLM_PORT="${1:-8080}" ;;
        --help)
            echo "Usage: ./scripts/test_llm_connectivity.sh [--host HOST] [--port PORT]"
            exit 0
            ;;
    esac
done
LLM_BASE_URL="http://${LLM_HOST}:${LLM_PORT}/v1"

echo -e "\n${BOLD}═══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}   openSUSE AI Assistant - LLM Connectivity Test    ${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}\n"
log_info "Target: ${LLM_BASE_URL}"

# ─── Test 1: Check HTTP Client Tools ───
log_step "Test 1: Checking HTTP client tools..."
if command -v curl &>/dev/null; then
    log_pass "curl $(curl --version | head -1 | awk '{print $2}')"
else
    log_fail "curl not found. Install: sudo zypper install -y curl"
    FAILED=$((FAILED + 1))
    exit 1
fi

if command -v python3.13 &>/dev/null; then
    log_pass "python3.13 $(python3.13 --version 2>&1 | awk '{print $2}')"
else
    log_warn "python3.13 not found locally (tests will use curl only)"
    WARNINGS=$((WARNINGS + 1))
fi

# ─── Test 2: TCP Connection ───
log_step "Test 2: TCP connection to ${LLM_HOST}:${LLM_PORT}..."
if timeout 5 bash -c "echo > /dev/tcp/${LLM_HOST}/${LLM_PORT}" 2>/dev/null; then
    log_pass "TCP connection established"
    PASSED=$((PASSED + 1))
else
    log_fail "Cannot connect to ${LLM_HOST}:${LLM_PORT}"
    log_error "Is the LLM server running?"
    log_error "  Start with: podman compose up -d"
    log_error "  Or:         python3.13 -m src.core.llm_server --port ${LLM_PORT}"
    FAILED=$((FAILED + 1))
    echo ""
    log_info "Results: ${GREEN}${PASSED} passed${NC}, ${RED}${FAILED} failed${NC}, ${YELLOW}${WARNINGS} warnings${NC}"
    exit 1
fi

# ─── Test 3: GET /v1/models ───
log_step "Test 3: GET /v1/models..."
MODELS_RESPONSE=$(curl -sf "${LLM_BASE_URL}/models" 2>&1) && {
    log_pass "/v1/models returned data"
    PASSED=$((PASSED + 1))
    # Extract model name
    MODEL_ID=$(echo "${MODELS_RESPONSE}" | python3.13 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('data'):
        print(data['data'][0].get('id', 'unknown'))
    else:
        print('no models listed')
except: print('parse error')
" 2>/dev/null || echo "parse error")
    log_info "Model: ${MODEL_ID}"
} || {
    log_fail "/v1/models request failed"
    FAILED=$((FAILED + 1))
}

# ─── Test 4: POST /v1/chat/completions ───
log_step "Test 4: POST /v1/chat/completions (simple prompt)..."
CHAT_RESPONSE=$(curl -sf -X POST "${LLM_BASE_URL}/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "default",
        "messages": [{"role": "user", "content": "Say hello in one word."}],
        "max_tokens": 20,
        "temperature": 0.0
    }' \
    --max-time 60 2>&1) && {
    log_pass "/v1/chat/completions returned response"
    PASSED=$((PASSED + 1))
    # Extract the response text
    REPLY_TEXT=$(echo "${CHAT_RESPONSE}" | python3.13 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    choice = data.get('choices', [{}])[0]
    msg = choice.get('message', {})
    print(msg.get('content', '(empty)').strip()[:100])
except: print('(parse error)')
" 2>/dev/null || echo "(parse error)")
    log_info "Reply: ${REPLY_TEXT}"
} || {
    log_fail "/v1/chat/completions request failed or timed out"
    FAILED=$((FAILED + 1))
}

# ─── Test 5: Response Time ───
log_step "Test 5: Response time measurement..."
START_MS=$(date +%s%N)
curl -sf -X POST "${LLM_BASE_URL}/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "default",
        "messages": [{"role": "user", "content": "Hi"}],
        "max_tokens": 10,
        "temperature": 0.0
    }' \
    --max-time 30 > /dev/null 2>&1
END_MS=$(date +%s%N)
ELAPSED_MS=$(( (END_MS - START_MS) / 1000000 ))

if [[ ${ELAPSED_MS} -lt 5000 ]]; then
    log_pass "Response time: ${ELAPSED_MS}ms (fast)"
    PASSED=$((PASSED + 1))
elif [[ ${ELAPSED_MS} -lt 15000 ]]; then
    log_pass "Response time: ${ELAPSED_MS}ms (acceptable)"
    PASSED=$((PASSED + 1))
elif [[ ${ELAPSED_MS} -lt 30000 ]]; then
    log_warn "Response time: ${ELAPSED_MS}ms (slow - consider GPU or smaller model)"
    PASSED=$((PASSED + 1))
    WARNINGS=$((WARNINGS + 1))
else
    log_fail "Response time: ${ELAPSED_MS}ms (too slow)"
    FAILED=$((FAILED + 1))
fi

# ─── Test 6: OpenAI Client Compatibility ───
log_step "Test 6: OpenAI client library compatibility..."
if python3.13 -c "
import sys
try:
    from openai import OpenAI
    client = OpenAI(base_url='${LLM_BASE_URL}', api_key='not-needed')
    resp = client.chat.completions.create(
        model='default',
        messages=[{'role': 'user', 'content': 'test'}],
        max_tokens=5
    )
    print('OK')
except ImportError:
    print('SKIP: openai not installed')
except Exception as e:
    print(f'ERROR: {e}')
" 2>/dev/null | grep -q "OK"; then
    log_pass "OpenAI Python client works"
    PASSED=$((PASSED + 1))
else
    OUTPUT=$(python3.13 -c "
import sys
try:
    from openai import OpenAI
    client = OpenAI(base_url='${LLM_BASE_URL}', api_key='not-needed')
    resp = client.chat.completions.create(
        model='default',
        messages=[{'role': 'user', 'content': 'test'}],
        max_tokens=5
    )
    print('OK')
except ImportError:
    print('SKIP: openai not installed')
except Exception as e:
    print(f'ERROR: {e}')
" 2>/dev/null || echo "ERROR")
    if echo "${OUTPUT}" | grep -q "SKIP"; then
        log_warn "OpenAI client test skipped (library not installed)"
        WARNINGS=$((WARNINGS + 1))
    else
        log_fail "OpenAI client test failed"
        FAILED=$((FAILED + 1))
    fi
fi

# ─── Summary ───
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}   Test Results                                       ${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}\n"
echo -e "  ${GREEN}Passed:  ${PASSED}${NC}"
echo -e "  ${RED}Failed:  ${FAILED}${NC}"
echo -e "  ${YELLOW}Warnings: ${WARNINGS}${NC}"
echo ""

if [[ ${FAILED} -eq 0 ]]; then
    log_info "All critical tests passed! The LLM server is operational."
    exit 0
else
    log_error "${FAILED} test(s) failed. Check logs above."
    exit 1
fi
