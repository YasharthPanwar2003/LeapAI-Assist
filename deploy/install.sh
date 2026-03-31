#!/bin/bash
# =============================================================================
# openSUSE AI Assistant - Master Install Script
# Platform: openSUSE Leap 16
# Installs: Python 3.13, Podman (or Docker), K3s/RKE2, all dependencies
# Usage: sudo ./install.sh [--docker | --podman] [--k3s | --rke2] [--all]
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_header() { echo -e "\n${BOLD}${BLUE}═══ $1 ═══${NC}\n"; }

CONTAINER_ENGINE="podman"
K8S_ENGINE=""
INSTALL_ALL=false

for arg in "$@"; do
    case $arg in
        --docker) CONTAINER_ENGINE="docker" ;;
        --podman) CONTAINER_ENGINE="podman" ;;
        --k3s) K8S_ENGINE="k3s" ;;
        --rke2) K8S_ENGINE="rke2" ;;
        --all) INSTALL_ALL=true ;;
        --help) echo "Usage: sudo ./install.sh [--docker|--podman] [--k3s|--rke2] [--all]"; exit 0 ;;
    esac
done

if [[ $INSTALL_ALL == true ]]; then
    K8S_ENGINE="k3s"
fi

# ─── System Update ───
log_header "Step 1: System Update"
log_step "Refreshing repositories and applying updates..."
sudo zypper refresh
sudo zypper update -y

# ─── Python 3.13 ───
log_header "Step 2: Python 3.13"
if rpm -q python313 &>/dev/null; then
    log_info "python313 $(rpm -q --queryformat '%{VERSION}' python313) already installed"
else
    log_step "Installing Python 3.13..."
    sudo zypper install -y python313 python313-pip python313-devel
fi

# ─── uv (Python package manager) ───
log_header "Step 3: uv Package Manager"
if command -v uv &>/dev/null; then
    log_info "uv $(uv --version 2>/dev/null | head -1) already installed"
else
    log_step "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | CARGO_HOME="$HOME/.cargo" sh
    export PATH="$HOME/.cargo/bin:$PATH"
fi

# ─── Container Engine ───
log_header "Step 4: Container Engine ($CONTAINER_ENGINE)"

if [[ "$CONTAINER_ENGINE" == "podman" ]]; then
    if rpm -q podman &>/dev/null; then
        log_info "podman $(rpm -q --queryformat '%{VERSION}' podman) already installed"
    else
        log_step "Installing Podman..."
        sudo zypper install -y podman podman-docker buildah skopeo
    fi
    # Verify podman compose
    if podman compose version &>/dev/null; then
        log_info "podman compose (built-in) available"
    else
        log_warn "podman compose not working. Try: sudo zypper install python313-podman-compose"
    fi

elif [[ "$CONTAINER_ENGINE" == "docker" ]]; then
    # Remove conflicting podman-docker
    if rpm -q podman-docker &>/dev/null; then
        log_warn "Removing podman-docker (conflicts with Docker CE)..."
        sudo zypper remove -y podman-docker
    fi
    if rpm -q docker &>/dev/null; then
        log_info "docker $(rpm -q --queryformat '%{VERSION}' docker) already installed"
    else
        log_step "Installing Docker CE..."
        sudo zypper addrepo https://download.docker.com/linux/sles/docker-ce.repo docker-ce-repo
        sudo zypper refresh
        sudo zypper install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        sudo systemctl enable --now docker
    fi
fi

# ─── Kubernetes Tools ───
log_header "Step 5: Kubernetes Tools"

# kubectl
if rpm -q kubernetes-client &>/dev/null; then
    log_info "kubernetes-client already installed"
else
    log_step "Installing kubectl..."
    sudo zypper install -y kubernetes-client
fi

# Helm
if command -v helm &>/dev/null; then
    log_info "helm $(helm version --short 2>/dev/null) already installed"
else
    log_step "Installing Helm..."
    sudo zypper install -y helm
fi

# K3s or RKE2
if [[ -n "$K8S_ENGINE" ]]; then
    log_step "Installing ${K8S_ENGINE}..."
    case $K8S_ENGINE in
        k3s)
            sudo zypper install -y k3s-server
            sudo systemctl enable --now k3s
            log_info "K3s installed. Nodes:"
            sudo k3s kubectl get nodes 2>/dev/null || true
            ;;
        rke2)
            sudo zypper install -y rke2-server
            sudo systemctl enable --now rke2-server
            log_info "RKE2 installed. Nodes:"
            sudo /var/lib/rancher/rke2/bin/kubectl get nodes 2>/dev/null || true
            ;;
    esac
fi

# ─── Application Setup ───
log_header "Step 6: Application Directories"
sudo mkdir -p /var/lib/suse-ai/{models,index,cache/docs,state,logs}
CURRENT_USER="${SUDO_USER:-$USER}"
CURRENT_GROUP="$(id -gn "$CURRENT_USER" 2>/dev/null || echo root)"
sudo chown -R "${CURRENT_USER}:${CURRENT_GROUP}" /var/lib/suse-ai
log_info "Directories created at /var/lib/suse-ai/"

# ─── Python Dependencies ───
log_header "Step 7: Python Dependencies"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/requirements.txt" ]]; then
    log_step "Installing Python dependencies..."
    uv pip install -r "${SCRIPT_DIR}/requirements.txt"
    log_info "Dependencies installed. Verify: uv pip list"
else
    log_warn "requirements.txt not found. Skipping."
fi

# ─── Summary ───
log_header "Installation Complete"
echo -e "  Container Engine: ${GREEN}${CONTAINER_ENGINE}${NC}"
echo -e "  Python: ${GREEN}3.13${NC}"
echo -e "  kubectl: ${GREEN}installed${NC}"
echo -e "  Helm: ${GREEN}installed${NC}"
[[ -n "$K8S_ENGINE" ]] && echo -e "  K8s Engine: ${GREEN}${K8S_ENGINE}${NC}"
echo ""
echo -e "  Next steps:"
echo -e "    1. Download models: ${YELLOW}./scripts/download_models.sh${NC}"
echo -e "    2. Build image:     ${YELLOW}./scripts/build_podman.sh${NC}"
echo -e "    3. Test:            ${YELLOW}./scripts/test_llm_connectivity.sh${NC}"
echo -e "    4. Run tests:       ${YELLOW}./scripts/run_firstboot_test.sh${NC}"
