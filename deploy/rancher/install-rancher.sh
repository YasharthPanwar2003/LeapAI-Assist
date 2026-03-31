#!/usr/bin/env bash
# =============================================================================
# install-rancher.sh — Install SUSE Rancher Prime via Helm on K3s/RKE2
#
# This script installs cert-manager and Rancher on an existing K3s or RKE2
# cluster using Helm 3. It configures the hostname, validates the installation,
# and shows access instructions.
#
# Usage:
#   sudo bash install-rancher.sh --hostname rancher.mydomain.com
#   sudo bash install-rancher.sh --hostname rancher.example.com --password MyPass123
#   sudo bash install-rancher.sh --hostname rancher.example.com --replicas 3
#
# Requirements:
#   - Existing K3s or RKE2 cluster (see install-k3s.sh or install-rke2.sh)
#   - Helm 3 installed
#   - kubectl configured with cluster access
#   - DNS record for hostname pointing to cluster ingress/LB
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Color output helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()  { echo -e "${CYAN}[STEP]${NC}  $*"; }

# ---------------------------------------------------------------------------
# Default values
# ---------------------------------------------------------------------------
RANCHER_HOSTNAME=""
RANCHER_PASSWORD=""
RANCHER_REPLICAS=1
RANCHER_VERSION=""
CERT_MANAGER_VERSION=""
RANCHER_NAMESPACE="cattle-system"
CERT_MANAGER_NAMESPACE="cert-manager"
SKIP_CERT_MANAGER=false
USE_LETSENCRYPT=false
USE_CUSTOM_TLS=false
CUSTOM_TLS_SECRET=""
VALUES_FILE=""

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --hostname)
            RANCHER_HOSTNAME="$2"
            shift 2
            ;;
        --password)
            RANCHER_PASSWORD="$2"
            shift 2
            ;;
        --replicas)
            RANCHER_REPLICAS="$2"
            shift 2
            ;;
        --version)
            RANCHER_VERSION="$2"
            shift 2
            ;;
        --cert-manager-version)
            CERT_MANAGER_VERSION="$2"
            shift 2
            ;;
        --namespace)
            RANCHER_NAMESPACE="$2"
            shift 2
            ;;
        --skip-cert-manager)
            SKIP_CERT_MANAGER=true
            shift
            ;;
        --letsencrypt)
            USE_LETSENCRYPT=true
            shift
            ;;
        --custom-tls)
            USE_CUSTOM_TLS=true
            CUSTOM_TLS_SECRET="$2"
            shift 2
            ;;
        --values)
            VALUES_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: sudo bash install-rancher.sh [OPTIONS]"
            echo ""
            echo "Install SUSE Rancher Prime on an existing K3s or RKE2 cluster."
            echo ""
            echo "Required:"
            echo "  --hostname HOSTNAME     Rancher hostname (e.g., rancher.mydomain.com)"
            echo ""
            echo "Optional:"
            echo "  --password PASS         Bootstrap password (auto-generated if omitted)"
            echo "  --replicas N            Number of Rancher replicas (default: 1)"
            echo "  --version VER           Rancher chart version (default: latest stable)"
            echo "  --cert-manager-version  cert-manager chart version"
            echo "  --namespace NS          Namespace for Rancher (default: cattle-system)"
            echo "  --skip-cert-manager     Skip cert-manager installation"
            echo "  --letsencrypt           Enable Let's Encrypt TLS (requires ingress)"
            echo "  --custom-tls SECRET     Use existing TLS secret name"
            echo "  --values FILE           Path to custom Helm values file"
            echo "  -h, --help              Show this help message"
            echo ""
            echo "Examples:"
            echo "  sudo bash install-rancher.sh --hostname rancher.mydomain.com"
            echo "  sudo bash install-rancher.sh --hostname rancher.example.com --replicas 3 --password AdminPass1"
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
step "Running pre-flight checks..."

# Check hostname
if [[ -z "$RANCHER_HOSTNAME" ]]; then
    error "--hostname is required (e.g., --hostname rancher.mydomain.com)"
    exit 1
fi

# Check kubectl
if ! command -v kubectl &>/dev/null; then
    # Try common kubectl locations
    if [[ -x /usr/local/bin/kubectl ]]; then
        export PATH="$PATH:/usr/local/bin"
    elif [[ -x /var/lib/rancher/rke2/bin/kubectl ]]; then
        export PATH="$PATH:/var/lib/rancher/rke2/bin"
    else
        error "kubectl not found. Please install kubectl or ensure it's in PATH."
        exit 1
    fi
fi
ok "kubectl found: $(command -v kubectl)"

# Check Helm
if ! command -v helm &>/dev/null; then
    error "helm not found. Install Helm 3 first:"
    error "  sudo zypper install helm"
    error "  or: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
    exit 1
fi
ok "Helm found: $(command -v helm) ($(helm version --short 2>/dev/null))"

# Check cluster connectivity
if ! kubectl cluster-info &>/dev/null; then
    error "Cannot connect to Kubernetes cluster. Check your kubeconfig."
    exit 1
fi
ok "Kubernetes cluster connectivity: OK"

# Check if we're running on K3s or RKE2
CLUSTER_TYPE="unknown"
if kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}' 2>/dev/null | grep -qi "k3s"; then
    CLUSTER_TYPE="K3s"
elif kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}' 2>/dev/null | grep -qi "rke2"; then
    CLUSTER_TYPE="RKE2"
fi
if [[ "$CLUSTER_TYPE" != "unknown" ]]; then
    ok "Detected cluster type: $CLUSTER_TYPE"
else
    info "Cluster type: generic Kubernetes"
fi

# Check for existing Rancher installation
if kubectl get namespace "$RANCHER_NAMESPACE" &>/dev/null; then
    if kubectl get deploy -n "$RANCHER_NAMESPACE" rancher &>/dev/null; then
        warn "Rancher appears to be already installed in namespace $RANCHER_NAMESPACE"
        read -p "Upgrade existing installation? [y/N] " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Aborting."
            exit 0
        fi
    fi
fi

# Generate bootstrap password if not provided
if [[ -z "$RANCHER_PASSWORD" ]]; then
    RANCHER_PASSWORD=$(openssl rand -base64 16 | tr -d '=/+' | head -c 20)
    info "Generated bootstrap password"
else
    info "Using provided bootstrap password"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 1: Install cert-manager
# ---------------------------------------------------------------------------
if [[ "$SKIP_CERT_MANAGER" == false ]]; then
    step "Step 1: Installing cert-manager..."

    # Check if cert-manager is already installed
    if kubectl get deploy -n "$CERT_MANAGER_NAMESPACE" cert-manager &>/dev/null 2>&1; then
        ok "cert-manager is already installed in namespace $CERT_MANAGER_NAMESPACE"
    else
        # Add Jetstack Helm repository
        helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
        helm repo update jetstack

        # Build cert-manager install command
        CERT_CMD="helm upgrade --install cert-manager jetstack/cert-manager \
            --namespace $CERT_MANAGER_NAMESPACE \
            --create-namespace \
            --set installCRDs=true"

        if [[ -n "$CERT_MANAGER_VERSION" ]]; then
            CERT_CMD="$CERT_CMD --version $CERT_MANAGER_VERSION"
        fi

        info "Running: $CERT_CMD"
        if eval "$CERT_CMD"; then
            ok "cert-manager installed successfully"
        else
            error "Failed to install cert-manager"
            exit 1
        fi
    fi

    # Wait for cert-manager pods to be ready
    info "Waiting for cert-manager pods to be ready..."
    kubectl rollout status deploy/cert-manager -n "$CERT_MANAGER_NAMESPACE" --timeout=120s
    kubectl rollout status deploy/cert-manager-cainjector -n "$CERT_MANAGER_NAMESPACE" --timeout=120s
    kubectl rollout status deploy/cert-manager-webhook -n "$CERT_MANAGER_NAMESPACE" --timeout=120s
    ok "cert-manager is ready"

    echo ""
else
    warn "Skipping cert-manager installation (--skip-cert-manager)"
fi

# ---------------------------------------------------------------------------
# Step 2: Add Rancher Helm repository
# ---------------------------------------------------------------------------
step "Step 2: Adding Rancher Helm repository..."

helm repo add rancher-stable https://releases.rancher.com/server-charts/stable 2>/dev/null || true
helm repo update rancher-stable
ok "Rancher Helm repository updated"

echo ""

# ---------------------------------------------------------------------------
# Step 3: Install Rancher
# ---------------------------------------------------------------------------
step "Step 3: Installing Rancher..."

# Build Helm install/upgrade command
RANCHER_CMD="helm upgrade --install rancher rancher-stable/rancher \
    --namespace $RANCHER_NAMESPACE \
    --create-namespace \
    --set hostname=$RANCHER_HOSTNAME \
    --set replicas=$RANCHER_REPLICAS \
    --set bootstrapPassword=$RANCHER_PASSWORD"

# Set TLS configuration
if [[ "$USE_LETSENCRYPT" == true ]]; then
    RANCHER_CMD="$RANCHER_CMD \
    --set ingress.tls.source=letsEncrypt \
    --set letsEncrypt.email=admin@${RANCHER_HOSTNAME#*.} \
    --set letsEncrypt.ingress.class=traefik"
    info "Let's Encrypt TLS: Enabled"
elif [[ "$USE_CUSTOM_TLS" == true && -n "$CUSTOM_TLS_SECRET" ]]; then
    RANCHER_CMD="$RANCHER_CMD \
    --set ingress.tls.source=secret \
    --set privateCA=true"
    info "Custom TLS secret: $CUSTOM_TLS_SECRET"
else
    # Default: Rancher generates self-signed cert via cert-manager
    RANCHER_CMD="$RANCHER_CMD --set ingress.tls.source=rancher"
    info "TLS: Rancher self-signed (default)"
fi

# Version pinning
if [[ -n "$RANCHER_VERSION" ]]; then
    RANCHER_CMD="$RANCHER_CMD --version $RANCHER_VERSION"
fi

# Custom values file
if [[ -n "$VALUES_FILE" && -f "$VALUES_FILE" ]]; then
    RANCHER_CMD="$RANCHER_CMD --values $VALUES_FILE"
    info "Using custom values file: $VALUES_FILE"
fi

info "Running Helm install/upgrade..."
echo ""
if eval "$RANCHER_CMD"; then
    ok "Rancher Helm chart installed successfully"
else
    error "Failed to install Rancher"
    exit 1
fi

echo ""

# ---------------------------------------------------------------------------
# Step 4: Wait for Rancher to be ready
# ---------------------------------------------------------------------------
step "Step 4: Waiting for Rancher deployment to be ready..."

kubectl rollout status deploy/rancher -n "$RANCHER_NAMESPACE" --timeout=300s
ok "Rancher deployment is ready"

echo ""

# ---------------------------------------------------------------------------
# Step 5: Validate installation
# ---------------------------------------------------------------------------
step "Step 5: Validating Rancher installation..."

echo ""
info "=== Rancher Pods ==="
kubectl get pods -n "$RANCHER_NAMESPACE"

echo ""
info "=== Rancher Ingress ==="
kubectl get ingress -n "$RANCHER_NAMESPACE"

echo ""
info "=== Rancher Services ==="
kubectl get svc -n "$RANCHER_NAMESPACE"

# Check cert-manager resources
if [[ "$SKIP_CERT_MANAGER" == false ]]; then
    echo ""
    info "=== Certificates ==="
    kubectl get certificates -n "$RANCHER_NAMESPACE" 2>/dev/null || info "(No custom certificates found)"
fi

# Check ClusterIssuers
echo ""
info "=== Cluster Issuers ==="
kubectl get clusterissuers 2>/dev/null || info "(No cluster issuers found)"

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
BOOTSTRAP_PASSWORD="$RANCHER_PASSWORD"

echo "============================================================="
echo -e "${GREEN}  Rancher Installation Complete!${NC}"
echo "============================================================="
echo ""
echo -e "${BLUE}Hostname:${NC}          https://$RANCHER_HOSTNAME"
echo -e "${BLUE}Bootstrap Password:${NC} ${BOOTSTRAP_PASSWORD}"
echo -e "${BLUE}Namespace:${NC}         $RANCHER_NAMESPACE"
echo -e "${BLUE}Replicas:${NC}          $RANCHER_REPLICAS"
echo -e "${BLUE}TLS:${NC}              $([ "$USE_LETSENCRYPT" == true ] && echo "Let's Encrypt" || ([ "$USE_CUSTOM_TLS" == true ] && echo "Custom Secret" || echo "Rancher self-signed"))"
echo ""
echo -e "${YELLOW}--- Access Instructions ---${NC}"
echo ""
echo "  1. Open your browser and navigate to:"
echo "     https://$RANCHER_HOSTNAME"
echo ""
echo "  2. If using self-signed TLS, accept the browser security warning."
echo ""
echo "  3. Login with the bootstrap password:"
echo "     ${BOOTSTRAP_PASSWORD}"
echo ""
echo "  4. Set a new admin password when prompted."
echo ""
echo -e "${YELLOW}--- Verify with CLI ---${NC}"
echo ""
echo "  # Check Rancher status"
echo "  kubectl get pods -n $RANCHER_NAMESPACE"
echo ""
echo "  # Get bootstrap password (retrieve later)"
echo "  kubectl get secret -n $RANCHER_NAMESPACE bootstrap-secret \\"
echo "    -o go-template='{{.data.bootstrapPassword|base64decode}}{{\"\\n\"}}'"
echo ""
echo "  # Check Rancher logs"
echo "  kubectl logs -n $RANCHER_NAMESPACE -l app=rancher --tail=50 -f"
echo ""
echo -e "${YELLOW}--- Next Steps ---${NC}"
echo ""
echo "  1. Configure your preferred authentication (LDAP, SAML, GitHub, etc.)"
echo "  2. Set up cluster provisioning (RKE2, K3s, EKS, AKS, GKE)"
echo "  3. Enable Fleet GitOps for continuous delivery"
echo "  4. Install Rancher Monitoring (Prometheus/Grafana)"
echo "  5. Configure Longhorn for persistent storage"
echo ""
echo -e "${YELLOW}--- Upgrade Rancher Later ---${NC}"
echo ""
echo "  helm upgrade rancher rancher-stable/rancher \\"
echo "    --namespace $RANCHER_NAMESPACE \\"
echo "    --reuse-values"
echo ""
echo -e "${YELLOW}--- Uninstall Rancher ---${NC}"
echo ""
echo "  helm uninstall rancher --namespace $RANCHER_NAMESPACE"
echo "  kubectl delete namespace $RANCHER_NAMESPACE"
echo ""
echo "============================================================="
