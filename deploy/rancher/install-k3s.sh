#!/usr/bin/env bash
# =============================================================================
# install-k3s.sh — Install K3s on openSUSE Leap 16
#
# This script installs K3s in single-node or HA mode, configures kubeconfig,
# and optionally sets up an external database or Traefik ingress.
#
# Usage:
#   sudo bash install-k3s.sh                    # Single node (default)
#   sudo bash install-k3s.sh --ha               # HA mode with embedded etcd
#   sudo bash install-k3s.sh --token SECRET     # Custom cluster token
#   sudo bash install-k3s.sh --no-traefik       # Disable Traefik ingress
#   sudo bash install-k3s.sh --db mysql://...   # External database
#
# Requirements:
#   - openSUSE Leap 16 (or SLES 16)
#   - Root privileges (sudo)
#   - Minimum 1 CPU core, 2 GB RAM (single node)
#   - Minimum 2 CPU cores, 4 GB RAM (HA mode)
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Color output helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
CLUSTER_TOKEN=""
HA_MODE=false
DISABLE_TRAEFIK=false
EXTERNAL_DB=""
INSTALL_CLI_TOOLS=false
CONFIG_OVERWRITE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --token)
            CLUSTER_TOKEN="$2"
            shift 2
            ;;
        --ha)
            HA_MODE=true
            shift
            ;;
        --no-traefik)
            DISABLE_TRAEFIK=true
            shift
            ;;
        --db)
            EXTERNAL_DB="$2"
            shift 2
            ;;
        --cli-tools)
            INSTALL_CLI_TOOLS=true
            shift
            ;;
        --overwrite-config)
            CONFIG_OVERWRITE=true
            shift
            ;;
        -h|--help)
            echo "Usage: sudo bash install-k3s.sh [OPTIONS]"
            echo ""
            echo "Install K3s on openSUSE Leap 16."
            echo ""
            echo "Options:"
            echo "  --token TOKEN          Set a custom cluster join token"
            echo "  --ha                   Install in HA mode (embedded etcd)"
            echo "  --no-traefik           Disable Traefik ingress controller"
            echo "  --db URL               Use external database (MySQL/PostgreSQL)"
            echo "  --cli-tools            Install kubectl, helm, and crictl"
            echo "  --overwrite-config     Overwrite existing K3s config"
            echo "  -h, --help             Show this help message"
            echo ""
            echo "Examples:"
            echo "  sudo bash install-k3s.sh"
            echo "  sudo bash install-k3s.sh --ha --token mytoken123"
            echo "  sudo bash install-k3s.sh --db 'mysql://k3s:pass@tcp(10.0.0.1:3306)/k3s'"
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

if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)."
    exit 1
fi

# Detect OS
if [[ ! -f /etc/os-release ]]; then
    error "Cannot detect OS: /etc/os-release not found."
    exit 1
fi

source /etc/os-release

if [[ "$ID" != "opensuse-leap" && "$ID" != "sles" ]]; then
    warn "Detected OS: $PRETTY_NAME"
    warn "This script is designed for openSUSE Leap 16 / SLES 16."
else
    ok "Detected OS: $PRETTY_NAME"
fi

# Check architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|aarch64|armv7l)
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
MEM_MB=$((MEM_KB / 1024))

if [[ "$HA_MODE" == true ]]; then
    MIN_CPU=2
    MIN_MEM=4096
else
    MIN_CPU=1
    MIN_MEM=2048
fi

if [[ $CPU_CORES -lt $MIN_CPU ]]; then
    warn "Only $CPU_CORES CPU core(s). $MIN_CPU+ recommended for ${HA_MODE}HA mode."
fi
if [[ $MEM_MB -lt $MIN_MEM ]]; then
    warn "Only ${MEM_MB}MB RAM. ${MIN_MEM}MB+ recommended."
fi
ok "Resources: ${CPU_CORES} CPU cores, ${MEM_MB} MB RAM"

# Check if K3s is already installed
if systemctl is-active --quiet k3s 2>/dev/null || [[ -x /usr/local/bin/k3s ]]; then
    warn "K3s appears to be already installed."
    if [[ "$CONFIG_OVERWRITE" == false ]]; then
        warn "Use --overwrite-config if you want to reconfigure."
        warn "Proceeding with installation (zypper will handle upgrades)..."
    fi
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
# Configure K3s
# ---------------------------------------------------------------------------
info "Configuring K3s..."

K3S_CONFIG_DIR="/etc/rancher/k3s"
K3S_CONFIG_FILE="$K3S_CONFIG_DIR/config.yaml"

mkdir -p "$K3S_CONFIG_DIR"

# Build K3s server arguments
K3S_ARGS="server"

# HA mode: use embedded etcd (requires 3+ server nodes)
if [[ "$HA_MODE" == true ]]; then
    K3S_ARGS="$K3S_ARGS --cluster-init --token=$CLUSTER_TOKEN"
    info "HA mode enabled with embedded etcd (cluster-init)"
else
    K3S_ARGS="$K3S_ARGS --token=$CLUSTER_TOKEN"
    info "Single-node mode"
fi

# External database
if [[ -n "$EXTERNAL_DB" ]]; then
    K3S_ARGS="$K3S_ARGS --datastore-endpoint=$EXTERNAL_DB"
    info "External database configured: ${EXTERNAL_DB%%:*}://..."
fi

# Disable Traefik
if [[ "$DISABLE_TRAEFIK" == true ]]; then
    K3S_ARGS="$K3S_ARGS --disable traefik"
    info "Traefik ingress controller: DISABLED"
else
    info "Traefik ingress controller: ENABLED (default)"
fi

# Write config file
if [[ -f "$K3S_CONFIG_FILE" && "$CONFIG_OVERWRITE" == false ]]; then
    warn "K3s config already exists at $K3S_CONFIG_FILE — skipping"
else
    cat > "$K3S_CONFIG_FILE" <<EOF
# K3s Server Configuration for openSUSE Leap 16
# Generated by install-k3s.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)

# Write kubeconfig for local access
write-kubeconfig-mode: "0644"

# Disable unused components
disable:
  - servicelb

EOF

    if [[ "$DISABLE_TRAEFIK" == true ]]; then
        echo "disable:" >> "$K3S_CONFIG_FILE"
        echo "  - traefik" >> "$K3S_CONFIG_FILE"
    fi

    if [[ -n "$EXTERNAL_DB" ]]; then
        cat >> "$K3S_CONFIG_FILE" <<EOF

# External database
datastore-endpoint: "${EXTERNAL_DB}"
EOF
    fi

    if [[ "$HA_MODE" == true ]]; then
        cat >> "$K3S_CONFIG_FILE" <<EOF

# HA cluster initialization
cluster-init: true
token: "${CLUSTER_TOKEN}"
EOF
    fi

    ok "K3s config written to $K3S_CONFIG_FILE"
fi

# ---------------------------------------------------------------------------
# Install K3s via zypper
# ---------------------------------------------------------------------------
info "Installing K3s server via zypper..."

zypper --non-interactive refresh || warn "zypper refresh returned non-zero (may be non-fatal)"

if zypper --non-interactive install -y k3s-server; then
    ok "K3s server package installed"
else
    error "Failed to install k3s-server package"
    exit 1
fi

# ---------------------------------------------------------------------------
# Enable and start K3s
# ---------------------------------------------------------------------------
info "Enabling and starting K3s server..."

# Configure the service with our arguments if not using config file approach
if [[ -n "$EXTERNAL_DB" || "$HA_MODE" == true || "$DISABLE_TRAEFIK" == true ]]; then
    # Create environment file for additional arguments
    mkdir -p /etc/systemd/system/k3s.service.d
    cat > /etc/systemd/system/k3s.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/local/bin/k3s ${K3S_ARGS}
EOF
    systemctl daemon-reload
fi

systemctl enable k3s

if systemctl start k3s; then
    ok "K3s server started"
else
    error "Failed to start k3s service"
    info "Check logs: journalctl -u k3s -n 50"
    exit 1
fi

# ---------------------------------------------------------------------------
# Wait for K3s to be ready
# ---------------------------------------------------------------------------
info "Waiting for K3s to become ready (this may take 1-3 minutes)..."

KUBECTL="/usr/local/bin/kubectl"
MAX_WAIT=180
WAITED=0

while [[ $WAITED -lt $MAX_WAIT ]]; do
    if [[ -x "$KUBECTL" ]] && $KUBECTL get nodes &>/dev/null; then
        NODE_STATUS=$($KUBECTL get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        if [[ "$NODE_STATUS" == "True" ]]; then
            ok "K3s node is Ready"
            break
        fi
    fi
    echo -n "."
    sleep 3
    WAITED=$((WAITED + 3))
done
echo ""

if [[ $WAITED -ge $MAX_WAIT ]]; then
    error "Timed out waiting for K3s to become ready after ${MAX_WAIT}s"
    info "Check logs with: journalctl -u k3s -n 50"
    exit 1
fi

# ---------------------------------------------------------------------------
# Configure kubeconfig
# ---------------------------------------------------------------------------
info "Configuring kubeconfig..."

KUBECONFIG_SOURCE="/etc/rancher/k3s/k3s.yaml"
REAL_USER="${SUDO_USER:-$(whoami)}"
REAL_HOME=$(eval echo "~$REAL_USER")

if [[ -f "$KUBECONFIG_SOURCE" ]]; then
    mkdir -p "$REAL_HOME/.kube"
    cp "$KUBECONFIG_SOURCE" "$REAL_HOME/.kube/config"
    chown -R "$REAL_USER" "$REAL_HOME/.kube"
    chmod 600 "$REAL_HOME/.kube/config"

    # Fix server URL for remote access (if needed)
    SERVER_IP=$(hostname -I | awk '{print $1}')
    if ! grep -q "${SERVER_IP}" "$REAL_HOME/.kube/config" 2>/dev/null; then
        sed -i "s|https://127.0.0.1:6443|https://${SERVER_IP}:6443|g" "$REAL_HOME/.kube/config"
    fi

    ok "kubeconfig copied to $REAL_HOME/.kube/config"
    ok "Server URL set to https://${SERVER_IP}:6443"
else
    warn "kubeconfig not yet available"
fi

export KUBECONFIG="$KUBECONFIG_SOURCE"
export PATH="$PATH:/usr/local/bin"

# ---------------------------------------------------------------------------
# Install CLI tools (optional)
# ---------------------------------------------------------------------------
if [[ "$INSTALL_CLI_TOOLS" == true ]]; then
    info "Installing CLI tools..."

    # kubectl (already included with K3s, but ensure it's in PATH)
    if [[ -x "/usr/local/bin/kubectl" ]]; then
        ok "kubectl already available at /usr/local/bin/kubectl"
    fi

    # Install helm
    if ! command -v helm &>/dev/null; then
        info "Installing Helm..."
        zypper --non-interactive install -y helm 2>/dev/null || {
            curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
        }
        ok "Helm installed"
    else
        ok "Helm already installed"
    fi

    # Install crictl
    if ! command -v crictl &>/dev/null; then
        info "Installing crictl..."
        zypper --non-interactive install -y cri-tools 2>/dev/null || {
            warn "cri-tools not available via zypper; skipping"
        }
    fi
fi

# ---------------------------------------------------------------------------
# Validate cluster
# ---------------------------------------------------------------------------
info "Validating K3s cluster..."

echo ""
info "=== Cluster Nodes ==="
$KUBECTL get nodes -o wide

echo ""
info "=== System Pods ==="
$KUBECTL get pods -n kube-system

echo ""
info "=== K3s Version ==="
$KUBECTL version --short 2>/dev/null || $KUBECTL version

# Check Traefik if enabled
if [[ "$DISABLE_TRAEFIK" == false ]]; then
    echo ""
    info "=== Traefik Ingress Controller ==="
    $KUBECTL get pods -n kube-system -l 'app.kubernetes.io/name=traefik' 2>/dev/null || \
        warn "Traefik pods not found yet"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
SERVER_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "============================================================="
echo -e "${GREEN}  K3s Installation Complete!${NC}"
echo "============================================================="
echo ""
echo -e "${BLUE}Mode:${NC}          $([ "$HA_MODE" == true ] && echo "HA (Embedded etcd)" || echo "Single Node")"
echo -e "${BLUE}Cluster Token:${NC} ${CLUSTER_TOKEN}"
echo -e "${BLUE}Server IP:${NC}     $SERVER_IP"
echo -e "${BLUE}Kubeconfig:${NC}    $REAL_HOME/.kube/config"
echo -e "${BLUE}Traefik:${NC}       $([ "$DISABLE_TRAEFIK" == true ] && echo "Disabled" || echo "Enabled")"
if [[ -n "$EXTERNAL_DB" ]]; then
    echo -e "${BLUE}Database:${NC}     ${EXTERNAL_DB%%:*}://..."
fi
echo ""

if [[ "$HA_MODE" == true ]]; then
    echo -e "${YELLOW}--- To join additional server nodes (HA): ---${NC}"
    echo ""
    echo "  sudo zypper install k3s-server"
    echo "  sudo mkdir -p /etc/rancher/k3s/"
    echo "  sudo tee /etc/rancher/k3s/config.yaml <<'EOF'"
    echo "  server: https://${SERVER_IP}:6443"
    echo "  token: ${CLUSTER_TOKEN}"
    echo "  EOF"
    echo "  sudo systemctl enable --now k3s"
    echo ""
fi

echo -e "${YELLOW}--- To join worker/agent nodes: ---${NC}"
echo ""
echo "  # 1. Install K3s agent"
echo "  sudo zypper install k3s-agent"
echo ""
echo "  # 2. Create config file"
echo "  sudo mkdir -p /etc/rancher/k3s/"
echo "  sudo tee /etc/rancher/k3s/config.yaml <<'AGENTCFG'"
echo "  server: https://${SERVER_IP}:6443"
echo "  token: ${CLUSTER_TOKEN}"
echo "  AGENTCFG"
echo ""
echo "  # 3. Enable and start K3s agent"
echo "  sudo systemctl enable --now k3s-agent"
echo ""
echo -e "${YELLOW}--- Useful Commands ---${NC}"
echo ""
echo "  # Check node status"
echo "  /usr/local/bin/kubectl get nodes"
echo ""
echo "  # View K3s logs"
echo "  sudo journalctl -u k3s -f"
echo ""
echo "  # Access Traefik dashboard"
echo "  kubectl port-forward -n kube-system svc/traefik 9000:9000"
echo "  # Then open http://localhost:9000/dashboard/"
echo ""
echo "  # Uninstall K3s"
echo "  /usr/local/bin/k3s-uninstall.sh"
echo ""
echo "============================================================="
