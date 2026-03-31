#!/usr/bin/env bash
# =============================================================================
# install-rke2.sh — Install RKE2 (Rancher Kubernetes Engine 2) on openSUSE Leap 16
#
# This script installs RKE2 server on the current node, configures kubeconfig,
# validates the cluster, and displays join commands for worker nodes.
#
# Usage:
#   sudo bash install-rke2.sh                    # Install with defaults
#   sudo bash install-rke2.sh --token SECRET123  # Custom cluster token
#   sudo bash install-rke2.sh --cis              # Enable CIS hardening profile
#
# Requirements:
#   - openSUSE Leap 16 (or SLES 16)
#   - Root privileges (sudo)
#   - Minimum 2 CPU cores, 4 GB RAM for control plane
#   - Network connectivity to SUSE package repositories
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Color output helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
CLUSTER_TOKEN=""
ENABLE_CIS=false
CONFIG_OVERWRITE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --token)
            CLUSTER_TOKEN="$2"
            shift 2
            ;;
        --cis)
            ENABLE_CIS=true
            shift
            ;;
        --overwrite-config)
            CONFIG_OVERWRITE=true
            shift
            ;;
        -h|--help)
            echo "Usage: sudo bash install-rke2.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --token TOKEN          Set a custom cluster join token"
            echo "  --cis                  Enable CIS hardening profile"
            echo "  --overwrite-config     Overwrite existing RKE2 config"
            echo "  -h, --help             Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
info "Running pre-flight checks..."

# Check root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)."
    exit 1
fi

# Detect openSUSE Leap 16
if [[ ! -f /etc/os-release ]]; then
    error "Cannot detect OS: /etc/os-release not found."
    exit 1
fi

source /etc/os-release

if [[ "$ID" != "opensuse-leap" && "$ID" != "sles" ]]; then
    warn "Detected OS: $PRETTY_NAME"
    warn "This script is designed for openSUSE Leap 16 / SLES 16."
    warn "Proceeding anyway..."
else
    ok "Detected OS: $PRETTY_NAME"
fi

# Check architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|aarch64)
        ok "Architecture: $ARCH (supported)"
        ;;
    *)
        error "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Check minimum resources
CPU_CORES=$(nproc)
MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEM_GB=$((MEM_KB / 1024 / 1024))

if [[ $CPU_CORES -lt 2 ]]; then
    warn "Only $CPU_CORES CPU core(s) detected. RKE2 recommends at least 2 cores."
fi
if [[ $MEM_GB -lt 4 ]]; then
    warn "Only ${MEM_GB}GB RAM detected. RKE2 recommends at least 4 GB."
fi
ok "Resources: ${CPU_CORES} CPU cores, ${MEM_GB} GB RAM"

# Check network connectivity
if ! ping -c 1 -W 5 download.opensuse.org &>/dev/null; then
    warn "Cannot reach download.opensuse.org — check network connectivity."
else
    ok "Network connectivity: OK"
fi

# ---------------------------------------------------------------------------
# Generate or use provided token
# ---------------------------------------------------------------------------
if [[ -z "$CLUSTER_TOKEN" ]]; then
    CLUSTER_TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '=/+' | head -c 32)
    info "Generated cluster token: ${CLUSTER_TOKEN:0:8}..."
else
    info "Using provided cluster token: ${CLUSTER_TOKEN:0:8}..."
fi

# ---------------------------------------------------------------------------
# Configure RKE2
# ---------------------------------------------------------------------------
info "Configuring RKE2..."

RKE2_CONFIG_DIR="/etc/rancher/rke2"
RKE2_CONFIG_FILE="$RKE2_CONFIG_DIR/config.yaml"

mkdir -p "$RKE2_CONFIG_DIR"

if [[ -f "$RKE2_CONFIG_FILE" && "$CONFIG_OVERWRITE" == false ]]; then
    warn "RKE2 config already exists at $RKE2_CONFIG_FILE"
    warn "Skipping config creation. Use --overwrite-config to overwrite."
else
    cat > "$RKE2_CONFIG_FILE" <<EOF
# RKE2 Server Configuration for openSUSE Leap 16
# Generated by install-rke2.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)

# Cluster token for node joining
token: "${CLUSTER_TOKEN}"

# Write kubeconfig for local access
write-kubeconfig-mode: "0644"

# Embedded etcd configuration
etcd-expose-metrics: true

# CNI: Canal (Calico + Flannel)
cni: canal

# Disable unused components
disable:
  - rke2-ingress-nginx

# Container runtime (containerd only — no change needed)
# containerd is the only runtime in RKE2

EOF

    if [[ "$ENABLE_CIS" == true ]]; then
        cat >> "$RKE2_CONFIG_FILE" <<EOF
# CIS Benchmark Hardening Profile
profile: "cis-1.8"

# Protect kernel defaults
protect-kernel-defaults: true

# Audit logging
audit-log-file: /var/lib/rancher/rke2/server/logs/audit.log
audit-log-maxage: 30
audit-log-maxbackup: 10
audit-log-maxsize: 100

# kube-apiserver args for CIS
kube-apiserver-arg:
  - "anonymous-auth=false"
  - "enable-admission-plugins=NodeRestriction,PodSecurityPolicy"
  - "profiling=false"

# kubelet args for CIS
kubelet-arg:
  - "event-qps=0"
  - "streaming-connection-idle-timeout=5m"
  - "protect-kernel-defaults=true"

EOF
        ok "CIS hardening profile enabled"
    fi

    ok "RKE2 config written to $RKE2_CONFIG_FILE"
fi

# ---------------------------------------------------------------------------
# Install RKE2 server
# ---------------------------------------------------------------------------
info "Installing RKE2 server via zypper..."

# Refresh package repositories
zypper --non-interactive refresh || warn "zypper refresh returned non-zero (may be non-fatal)"

# Install RKE2 server
if zypper --non-interactive install -y rke2-server; then
    ok "RKE2 server package installed successfully"
else
    error "Failed to install rke2-server package"
    exit 1
fi

# ---------------------------------------------------------------------------
# Enable and start RKE2
# ---------------------------------------------------------------------------
info "Enabling and starting RKE2 server..."
systemctl enable rke2-server

if systemctl start rke2-server; then
    ok "RKE2 server started"
else
    error "Failed to start Rke2-server service"
    exit 1
fi

# ---------------------------------------------------------------------------
# Wait for RKE2 to be ready
# ---------------------------------------------------------------------------
info "Waiting for RKE2 server to become ready (this may take 2-5 minutes)..."

KUBECTL="/var/lib/rancher/rke2/bin/kubectl"
MAX_WAIT=300
WAITED=0

while [[ $WAITED -lt $MAX_WAIT ]]; do
    if $KUBECTL get nodes &>/dev/null; then
        # Check if node is Ready
        NODE_STATUS=$($KUBECTL get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        if [[ "$NODE_STATUS" == "True" ]]; then
            ok "RKE2 node is Ready"
            break
        fi
    fi
    echo -n "."
    sleep 5
    WAITED=$((WAITED + 5))
done
echo ""

if [[ $WAITED -ge $MAX_WAIT ]]; then
    error "Timed out waiting for RKE2 to become ready after ${MAX_WAIT}s"
    info "Check logs with: journalctl -u rke2-server -n 50"
    exit 1
fi

# ---------------------------------------------------------------------------
# Configure kubeconfig for current user
# ---------------------------------------------------------------------------
info "Configuring kubeconfig..."

KUBECONFIG_SOURCE="/var/lib/rancher/rke2/agent/etc/kubeconfig.yaml"
KUBECONFIG_DEST="$HOME/.kube/config"

if [[ -f "$KUBECONFIG_SOURCE" ]]; then
    # Try to get the real user's home directory if running under sudo
    REAL_USER="${SUDO_USER:-$(whoami)}"
    REAL_HOME=$(eval echo "~$REAL_USER")

    mkdir -p "$REAL_HOME/.kube"
    cp "$KUBECONFIG_SOURCE" "$REAL_HOME/.kube/config"
    chown -R "$REAL_USER" "$REAL_HOME/.kube"
    chmod 600 "$REAL_HOME/.kube/config"
    ok "kubeconfig copied to $REAL_HOME/.kube/config"
else
    warn "kubeconfig not yet available at $KUBECONFIG_SOURCE"
    warn "After RKE2 fully initializes, run:"
    warn "  sudo cp $KUBECONFIG_SOURCE ~/.kube/config"
fi

# Export KUBECONFIG for this session
export KUBECONFIG="$KUBECONFIG_SOURCE"
export PATH="$PATH:/var/lib/rancher/rke2/bin"

# ---------------------------------------------------------------------------
# Validate cluster
# ---------------------------------------------------------------------------
info "Validating RKE2 cluster..."

echo ""
info "=== Cluster Nodes ==="
$KUBECTL get nodes -o wide

echo ""
info "=== System Pods ==="
$KUBECTL get pods -n kube-system

echo ""
info "=== Component Status ==="
$KUBECTL get cs 2>/dev/null || info "(ComponentStatus API deprecated in K8s 1.19+)"

echo ""
info "=== RKE2 Version ==="
$KUBECTL version --short 2>/dev/null || $KUBECTL version

# ---------------------------------------------------------------------------
# Display join instructions
# ---------------------------------------------------------------------------
SERVER_IP=$(hostname -I | awk '{print $1}')
NODE_TOKEN=$(/var/lib/rancher/rke2/server/node-token 2>/dev/null || echo "N/A")

echo ""
echo "============================================================="
echo -e "${GREEN}  RKE2 Server Installation Complete!${NC}"
echo "============================================================="
echo ""
echo -e "${BLUE}Cluster Token:${NC} $CLUSTER_TOKEN"
echo -e "${BLUE}Node Token:${NC}    $NODE_TOKEN"
echo -e "${BLUE}Server IP:${NC}     $SERVER_IP"
echo ""
echo -e "${YELLOW}--- To join worker nodes, run on each agent node: ---${NC}"
echo ""
echo "  # 1. Install RKE2 agent"
echo "  sudo zypper install rke2-agent"
echo ""
echo "  # 2. Create config file"
echo "  sudo mkdir -p /etc/rancher/rke2/"
echo "  sudo tee /etc/rancher/rke2/config.yaml <<'AGENTCFG'"
echo "  server: https://${SERVER_IP}:9345"
echo "  token: ${NODE_TOKEN}"
echo "  AGENTCFG"
echo ""
echo "  # 3. Enable and start RKE2 agent"
echo "  sudo systemctl enable --now rke2-agent"
echo ""
echo -e "${YELLOW}--- Useful Commands ---${NC}"
echo ""
echo "  # Check node status"
echo "  /var/lib/rancher/rke2/bin/kubectl get nodes"
echo ""
echo "  # View server logs"
echo "  sudo journalctl -u rke2-server -f"
echo ""
echo "  # Create an etcd snapshot"
echo "  sudo rke2 etcd-snapshot save --name my-snapshot"
echo ""
echo "  # Uninstall RKE2"
echo "  sudo zypper remove rke2-server"
echo "  sudo rm -rf /etc/rancher/rke2 /var/lib/rancher/rke2"
echo ""
echo "============================================================="
