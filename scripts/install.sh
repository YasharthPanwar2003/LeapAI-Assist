#!/bin/bash
# =============================================================================
# openSUSE AI Assistant - Master Install Script
# Platform: openSUSE Leap 16
# Installs: Python 3.13, Podman 5.x (rootless), K3s/RKE2, all dependencies
# Usage: sudo ./install.sh [--docker | --podman] [--k3s | --rke2] [--all]
#
# 2026 FIXES APPLIED:
#   - Removed podman.socket / podman.service references (Podman is DAEMONLESS)
#   - Added crun, slirp4netns, fuse-overlayfs (required for rootless containers)
#   - Added loginctl enable-linger (keeps user units alive after logout)
#   - Created Quadlet directory (~/.config/containers/systemd/)
#   - huggingface-cli → hf (huggingface_hub >= 1.8.0)
#   - Added subuid/subgid verification for rootless UID mapping
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
log_info()   { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()  { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()   { echo -e "${BLUE}[STEP]${NC} $1"; }
log_header() { echo -e "\n${BOLD}${BLUE}═══ $1 ═══${NC}\n"; }

CONTAINER_ENGINE="podman"
K8S_ENGINE=""
INSTALL_ALL=false

for arg in "$@"; do
    case $arg in
        --docker)  CONTAINER_ENGINE="docker" ;;
        --podman)  CONTAINER_ENGINE="podman" ;;
        --k3s)     K8S_ENGINE="k3s" ;;
        --rke2)    K8S_ENGINE="rke2" ;;
        --all)     INSTALL_ALL=true ;;
        --help)    echo "Usage: sudo ./install.sh [--docker|--podman] [--k3s|--rke2] [--all]"; exit 0 ;;
    esac
done

if [[ $INSTALL_ALL == true ]]; then
    K8S_ENGINE="k3s"
fi

# Resolve the actual invoking user (works under sudo)
CURRENT_USER="${SUDO_USER:-$USER}"
CURRENT_GROUP="$(id -gn "${CURRENT_USER}" 2>/dev/null || echo root)"
CURRENT_UID="$(id -u "${CURRENT_USER}")"

# ─── Step 1: System Update ───────────────────────────────────────────────────
log_header "Step 1: System Update"
log_step "Refreshing repositories and applying updates..."
zypper refresh
zypper update -y

# ─── Step 2: Python 3.13 ─────────────────────────────────────────────────────
log_header "Step 2: Python 3.13"
if rpm -q python313 &>/dev/null; then
    log_info "python313 $(rpm -q --queryformat '%{VERSION}' python313) already installed"
else
    log_step "Installing Python 3.13..."
    zypper install -y python313 python313-pip python313-devel
fi

# ─── Step 3: uv (Python package manager) ────────────────────────────────────
log_header "Step 3: uv Package Manager"
if command -v uv &>/dev/null; then
    log_info "uv $(uv --version 2>/dev/null | head -1) already installed"
else
    log_step "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | CARGO_HOME="/home/${CURRENT_USER}/.cargo" sh
    export PATH="/home/${CURRENT_USER}/.cargo/bin:$PATH"
fi

# ─── Step 4: Rootless Podman Stack (CRITICAL — must install before Podman) ──
# These three packages are mandatory for rootless container operation:
#   crun          — OCI runtime that Podman calls to actually run containers
#   slirp4netns   — user-space network stack for rootless network isolation
#   fuse-overlayfs — overlay filesystem driver that works without root
# Without all three, rootless containers will fail silently or with
# cryptic "permission denied" or "network unreachable" errors.
log_header "Step 4: Rootless Container Stack"
for pkg in crun slirp4netns fuse-overlayfs; do
    if rpm -q "${pkg}" &>/dev/null; then
        log_info "${pkg} $(rpm -q --queryformat '%{VERSION}' "${pkg}") already installed"
    else
        log_step "Installing ${pkg}..."
        zypper install -y "${pkg}"
    fi
done

# Verify /etc/subuid and /etc/subgid entries exist for the user.
# These files map the host user to a range of subordinate UIDs/GIDs inside
# containers. Without these entries, keep-id and user namespace mapping fail.
log_step "Verifying subuid/subgid entries for ${CURRENT_USER}..."
if grep -q "^${CURRENT_USER}:" /etc/subuid 2>/dev/null; then
    log_info "subuid entry found: $(grep "^${CURRENT_USER}:" /etc/subuid)"
else
    log_warn "No subuid entry for ${CURRENT_USER} — adding default range..."
    echo "${CURRENT_USER}:100000:65536" >> /etc/subuid
fi
if grep -q "^${CURRENT_USER}:" /etc/subgid 2>/dev/null; then
    log_info "subgid entry found: $(grep "^${CURRENT_USER}:" /etc/subgid)"
else
    log_warn "No subgid entry for ${CURRENT_USER} — adding default range..."
    echo "${CURRENT_USER}:100000:65536" >> /etc/subgid
fi

# ─── Step 5: loginctl enable-linger ─────────────────────────────────────────
# Without lingering, ALL user systemd services — including Quadlet containers —
# are killed immediately when the user's last session ends (SSH logout, etc.).
# Linger keeps the user's systemd --user instance running persistently so that
# Quadlet-managed containers survive reboots and session disconnects.
log_header "Step 5: Persistent User Session (loginctl linger)"
log_step "Enabling linger for ${CURRENT_USER} (UID ${CURRENT_UID})..."
loginctl enable-linger "${CURRENT_USER}"

# Verify linger is active
LINGER_STATUS=$(loginctl show-user "${CURRENT_USER}" --property=Linger --value 2>/dev/null || echo "unknown")
if [[ "${LINGER_STATUS}" == "yes" ]]; then
    log_info "Linger enabled: ${LINGER_STATUS}"
else
    log_warn "Linger status: ${LINGER_STATUS} — reboot may be required"
fi

# ─── Step 6: Container Engine ───────────────────────────────────────────────
log_header "Step 6: Container Engine ($CONTAINER_ENGINE)"

if [[ "$CONTAINER_ENGINE" == "podman" ]]; then
    if rpm -q podman &>/dev/null; then
        log_info "podman $(rpm -q --queryformat '%{VERSION}' podman) already installed"
    else
        log_step "Installing Podman 5.x..."
        zypper install -y podman podman-docker buildah skopeo
    fi

    # NOTE: Podman is DAEMONLESS. There is no podman.service or podman.socket
    # to start or enable. Do NOT run:
    #   systemctl --user enable --now podman.socket   ← WRONG, will fail
    #   systemctl enable podman.service                ← WRONG, does not exist
    # Podman spawns the container process directly as a child of the caller.

    # Verify podman compose (built-in in Podman 5.x)
    if podman compose version &>/dev/null 2>&1; then
        log_info "podman compose (built-in) available: $(podman compose version --short 2>/dev/null || echo 'ok')"
    else
        log_warn "podman compose not working — try: zypper install python313-podman-compose"
    fi

    # Create Quadlet directory for user-scoped container units.
    # Quadlets (.container, .pod, .network, .volume files placed here) are
    # auto-converted to systemd service units by systemd-generator on daemon-reload.
    # This is the RECOMMENDED way to run containers as services in Podman 5.x.
    # The deprecated alternative (podman generate systemd) should NOT be used.
    QUADLET_DIR="/home/${CURRENT_USER}/.config/containers/systemd"
    log_step "Creating Quadlet directory: ${QUADLET_DIR}"
    mkdir -p "${QUADLET_DIR}"
    chown "${CURRENT_USER}:${CURRENT_GROUP}" "${QUADLET_DIR}"
    chmod 700 "${QUADLET_DIR}"
    log_info "Quadlet directory ready. Place .container/.pod files here."

    # Also ensure the user systemd unit directory exists
    USER_SYSTEMD_DIR="/home/${CURRENT_USER}/.config/systemd/user"
    mkdir -p "${USER_SYSTEMD_DIR}"
    chown -R "${CURRENT_USER}:${CURRENT_GROUP}" "${USER_SYSTEMD_DIR}"

elif [[ "$CONTAINER_ENGINE" == "docker" ]]; then
    # Remove podman-docker shim — it conflicts with real Docker CE
    if rpm -q podman-docker &>/dev/null; then
        log_warn "Removing podman-docker (conflicts with Docker CE)..."
        zypper remove -y podman-docker
    fi
    if rpm -q docker &>/dev/null; then
        log_info "docker $(rpm -q --queryformat '%{VERSION}' docker) already installed"
    else
        log_step "Installing Docker CE..."
        zypper addrepo https://download.docker.com/linux/sles/docker-ce.repo docker-ce-repo
        zypper refresh
        zypper install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        systemctl enable --now docker
    fi
fi

# ─── Step 7: Kubernetes Tools ────────────────────────────────────────────────
log_header "Step 7: Kubernetes Tools"

if rpm -q kubernetes-client &>/dev/null; then
    log_info "kubernetes-client already installed"
else
    log_step "Installing kubectl..."
    zypper install -y kubernetes-client
fi

if command -v helm &>/dev/null; then
    log_info "helm $(helm version --short 2>/dev/null) already installed"
else
    log_step "Installing Helm..."
    zypper install -y helm
fi

if [[ -n "$K8S_ENGINE" ]]; then
    log_step "Installing ${K8S_ENGINE}..."
    case $K8S_ENGINE in
        k3s)
            zypper install -y k3s-server
            systemctl enable --now k3s
            log_info "K3s installed. Nodes:"
            k3s kubectl get nodes 2>/dev/null || true
            ;;
        rke2)
            zypper install -y rke2-server
            systemctl enable --now rke2-server
            log_info "RKE2 installed. Nodes:"
            /var/lib/rancher/rke2/bin/kubectl get nodes 2>/dev/null || true
            ;;
    esac
fi

# ─── Step 8: Application Directories ────────────────────────────────────────
log_header "Step 8: Application Directories"
mkdir -p /var/lib/suse-ai/{models,index,cache/docs,state,logs,documents}
chown -R "${CURRENT_USER}:${CURRENT_GROUP}" /var/lib/suse-ai
chmod 755 /var/lib/suse-ai
chmod 700 /var/lib/suse-ai/state
log_info "Directories created at /var/lib/suse-ai/"

# ─── Step 9: Python Dependencies ────────────────────────────────────────────
log_header "Step 9: Python Dependencies"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/requirements.txt" ]]; then
    log_step "Installing Python dependencies via uv..."
    sudo -u "${CURRENT_USER}" uv pip install -r "${SCRIPT_DIR}/requirements.txt"
    log_info "Dependencies installed."
else
    log_warn "requirements.txt not found at ${SCRIPT_DIR}/requirements.txt — skipping."
fi

# ─── Step 10: Verify hf CLI (replaces deprecated huggingface-cli) ───────────
log_header "Step 10: Hugging Face CLI (hf)"
# huggingface-cli was removed in huggingface_hub >= 1.0.
# The new command is 'hf'. Verify it is available.
if command -v hf &>/dev/null; then
    log_info "hf CLI found: $(hf version 2>/dev/null | head -1)"
elif python3.13 -c "from huggingface_hub.cli import app" &>/dev/null 2>&1; then
    log_info "hf available via python3.13 -m huggingface_hub"
else
    log_warn "'hf' CLI not found. Install: uv pip install 'huggingface_hub[cli]>=1.8.0'"
    log_warn "Then run: hf auth login"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
log_header "Installation Complete"
echo -e "  Container Engine : ${GREEN}${CONTAINER_ENGINE}${NC}"
echo -e "  Python           : ${GREEN}3.13${NC}"
echo -e "  kubectl          : ${GREEN}installed${NC}"
echo -e "  Helm             : ${GREEN}installed${NC}"
echo -e "  Rootless stack   : ${GREEN}crun + slirp4netns + fuse-overlayfs${NC}"
echo -e "  Linger           : ${GREEN}${LINGER_STATUS:-enabled}${NC}"
[[ -n "$K8S_ENGINE" ]] && echo -e "  K8s Engine       : ${GREEN}${K8S_ENGINE}${NC}"
echo ""
echo -e "  Next steps:"
echo -e "    1. Login to HF Hub: ${YELLOW}hf auth login${NC}"
echo -e "    2. Download models: ${YELLOW}./scripts/download_models.sh${NC}"
echo -e "    3. Build image:     ${YELLOW}./scripts/build_podman.sh${NC}"
echo -e "    4. Test:            ${YELLOW}./scripts/test_llm_connectivity.sh${NC}"
echo -e "    5. Run firstboot:   ${YELLOW}./scripts/run_firstboot_test.sh${NC}"
