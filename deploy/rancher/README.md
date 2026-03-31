# SUSE Rancher Prime on openSUSE Leap 16

> **Last Updated:** March 2026
> **Platform:** openSUSE Leap 16 / SUSE Linux Enterprise Server 16
> **Rancher Version:** 2.10+ (SUSE Rancher Prime)

---

## Table of Contents

- [Overview](#overview)
- [SUSE + Rancher Relationship](#suse--rancher-relationship)
- [RKE2 — Enterprise Kubernetes Distribution](#rke2--enterprise-kubernetes-distribution)
- [K3s — Lightweight Kubernetes for Edge/IoT](#k3s--lightweight-kubernetes-for-edgeiot)
- [Rancher Installation via Helm](#rancher-installation-via-helm)
- [RKE2 vs K3s Comparison](#rke2-vs-k3s-comparison)
- [Fleet GitOps](#fleet-gitops)
- [Cluster Provisioning](#cluster-provisioning)
- [RBAC and Multi-Tenancy](#rbac-and-multi-tenancy)
- [Backup and Restore](#backup-and-restore)
- [Monitoring (Prometheus/Grafana)](#monitoring-prometheusgrafana)
- [SUSE Virtualization Unification](#suse-virtualization-unification)
- [Troubleshooting](#troubleshooting)

---

## Overview

**SUSE Rancher Prime** is SUSE's enterprise Kubernetes management platform. It provides a
single pane of glass for managing multiple Kubernetes clusters — whether they run on-premises,
in the cloud, or at the edge. Rancher delivers:

- **Centralized cluster management** — provision, operate, and secure K8s clusters anywhere
- **Built-in CI/CD** with Fleet for GitOps-based continuous delivery
- **App marketplace** with certified Helm charts and SUSE Prime applications
- **Security & compliance** — CIS benchmarks, RBAC, Pod Security Policies, secrets encryption
- **Multi-cluster networking** with Submariner for cross-cluster service discovery
- **AI/ML workloads** — GPU scheduling, model serving, and SUSE's open agentic AI ecosystem
  (announced at KubeCon EU 2026)

As of March 2026, SUSE has expanded Rancher to integrate with its open agentic AI ecosystem,
enabling enterprises to deploy, manage, and scale AI agents alongside traditional containerized
workloads within the same Kubernetes management plane.

---

## SUSE + Rancher Relationship

SUSE acquired Rancher Labs in 2020 and now offers it as **SUSE Rancher Prime**, the commercially
supported edition. Key facts:

| Aspect | Details |
|---|---|
| **Product** | SUSE Rancher Prime |
| **Editions** | Rancher Prime (supported) vs. Rancher Community (upstream) |
| **Support** | Included with SUSE subscription; backed by SUSE engineering |
| **Kubernetes Distros** | RKE2 (enterprise), K3s (lightweight/edge) |
| **Package Manager** | Native zypper packages on Leap 16 / SLES 16 |
| **Certified On** | SLES, openSUSE Leap, SUSE Rancher OS, all major clouds |
| **AI Integration** | Open agentic AI ecosystem (KubeCon EU 2026) |

---

## RKE2 — Enterprise Kubernetes Distribution

RKE2 (Rancher Kubernetes Engine 2) is SUSE's **CNCF-certified, enterprise-grade** Kubernetes
distribution. It is fully packaged for openSUSE Leap 16 via zypper.

### Install RKE2 Server (Control Plane)

```bash
# Install RKE2 server package
sudo zypper install rke2-server

# Enable and start the service
sudo systemctl enable --now rke2-server

# Retrieve kubeconfig
sudo cat /var/lib/rancher/rke2/agent/etc/kubeconfig.yaml

# Or copy to your local kubectl config
mkdir -p ~/.kube
sudo cp /var/lib/rancher/rke2/agent/etc/kubeconfig.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# Verify cluster
/var/lib/rancher/rke2/bin/kubectl get nodes
```

### Install RKE2 Agent (Worker Node)

```bash
# Install RKE2 agent package
sudo zypper install rke2-agent

# Configure the server URL and token
sudo mkdir -p /etc/rancher/rke2/
sudo tee /etc/rancher/rke2/config.yaml <<EOF
server: https://<SERVER_IP>:9345
token: <CLUSTER_TOKEN>
EOF

# Enable and start the agent
sudo systemctl enable --now rke2-agent
```

### Retrieve Cluster Join Token (from server node)

```bash
sudo cat /var/lib/rancher/rke2/server/node-token
```

### Advanced RKE2 Configuration

See [`rke2-config.yaml`](./rke2-config.yaml) for a hardened CIS benchmark configuration example.

---

## K3s — Lightweight Kubernetes for Edge/IoT

K3s is a **single-binary**, lightweight Kubernetes distribution optimized for resource-constrained
environments, edge computing, and IoT deployments. It is also available as a zypper package on
Leap 16.

### Install K3s Server (Single Node)

```bash
# Install via zypper
sudo zypper install k3s-server

# Enable and start
sudo systemctl enable --now k3s

# Verify
/usr/local/bin/kubectl get nodes
```

### Install K3s Server (HA Multi-Node)

```bash
# Option 1: zypper (recommended for Leap 16)
sudo zypper install k3s-server

# Option 2: Install script with cluster-init for embedded etcd HA
curl -sfL https://get.k3s.io | sh -s - server \
  --cluster-init \
  --token=SECRET

# Join additional server nodes
curl -sfL https://get.k3s.io | sh -s - server \
  --server https://<FIRST_SERVER_IP>:6443 \
  --token=SECRET
```

### Install K3s Agent

```bash
# Install K3s agent package
sudo zypper install k3s-agent

# Configure to join a server
sudo mkdir -p /etc/rancher/k3s/
sudo tee /etc/rancher/k3s/config.yaml <<EOF
server: https://<SERVER_IP>:6443
token: <CLUSTER_TOKEN>
EOF

sudo systemctl enable --now k3s-agent
```

### External Database (MySQL/PostgreSQL) for K3s HA

```bash
# Install K3s with external datastore
curl -sfL https://get.k3s.io | sh -s - server \
  --datastore-endpoint="mysql://user:password@tcp(hostname:3306)/k3s"
```

### Traefik Ingress Controller

K3s ships with Traefik as the default ingress controller. To customize:

```bash
# Disable Traefik during install
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik" sh -

# Or uninstall post-install
/usr/local/bin/kubectl -n kube-system delete helmchart traefik
```

---

## Rancher Installation via Helm

Rancher is installed **on top of** an existing K3s or RKE2 cluster. The recommended method
is Helm 3.

### Prerequisites

- A running K3s or RKE2 cluster
- Helm 3 installed
- A DNS record pointing to the Rancher load balancer/ingress

### Step 1: Install cert-manager

```bash
# Add the Jetstack Helm repository
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install cert-manager (required for Rancher TLS)
helm install cert-manager jetstack/cert-manager \
  -n cert-manager \
  --create-namespace \
  --set installCRDs=true

# Verify cert-manager pods are running
kubectl get pods -n cert-manager
```

### Step 2: Install Rancher

```bash
# Add the Rancher stable Helm repository
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update

# Install Rancher
helm install rancher rancher-stable/rancher \
  -n cattle-system \
  --create-namespace \
  --set hostname=rancher.mydomain.com \
  --set replicas=3

# For custom values, use:
# helm install rancher rancher-stable/rancher \
#   -n cattle-system \
#   --create-namespace \
#   -f helm-values-rancher.yaml

# Verify Rancher is running
kubectl -n cattle-system rollout status deploy/rancher
kubectl get pods -n cattle-system
```

### Step 3: Verify Installation

```bash
# Check the ingress
kubectl get ingress -n cattle-system

# Retrieve the bootstrap password
kubectl get secret -n cattle-system bootstrap-secret \
  -o go-template='{{.data.bootstrapPassword|base64decode}}{{"\n"}}'

# Access Rancher at https://rancher.mydomain.com
# Login with the bootstrap password, then set a new admin password
```

See [`install-rancher.sh`](./install-rancher.sh) for the automated installation script and
[`helm-values-rancher.yaml`](./helm-values-rancher.yaml) for example Helm values.

---

## RKE2 vs K3s Comparison

| Feature | **RKE2** | **K3s** |
|---|---|---|
| **Target** | Enterprise/data center workloads | Edge, IoT, resource-constrained |
| **Binary Size** | ~200 MB | ~100 MB |
| **CIS Benchmark** | Full CIS 1.8+ hardening profile | Partial CIS support |
| **ETCD** | Embedded etcd (HA by default) | SQLite (single) / etcd/MySQL/PostgreSQL (HA) |
| **CNI** | Canal (Calico + Flannel) by default | Flannel by default |
| **Container Runtime** | containerd (only) | containerd (only) |
| **Ingress Controller** | NGINX (optional) | Traefik (bundled) |
| **Datastore** | etcd | SQLite, etcd, MySQL, PostgreSQL |
| **Package Management** | Single binary + systemd | Single binary + systemd |
| **zypper Available** | Yes (`rke2-server`, `rke2-agent`) | Yes (`k3s-server`, `k3s-agent`) |
| **Cloud Provider Integrations** | Full (CCM, CSI) | Partial (in-tree drivers) |
| **Audit Logging** | Built-in | Limited |
| **ARM Support** | Yes | Yes (primary target) |
| **Recommended Nodes** | 3+ control plane | 1–3 nodes |
| **Ideal Use Cases** | Production workloads, multi-cluster, AI/ML | Edge gateways, CI/CD runners, IoT, dev/test |

For a detailed comparison, see [`rke2-vs-k3s-comparison.md`](./rke2-vs-k3s-comparison.md).

---

## Fleet GitOps

[Fleet](https://fleet.rancher.io/) is Rancher's **GitOps continuous delivery** tool. It deploys
and manages workloads across multiple clusters from Git repositories.

### Key Concepts

- **Bundle**: A Fleet Bundle defines a set of Kubernetes resources to deploy
- **GitRepo**: A Fleet GitRepo watches a Git repository for changes
- **Target Clusters**: Clusters can be selected by labels, names, or cluster groups
- **Fleet Agent**: Runs on each managed cluster; communicates with the Fleet controller

### Example GitRepo

See [`fleet-gitrepo.yaml`](./fleet-gitrepo.yaml) for a complete example.

### How Fleet Works

```
  Git Repository
       │
       ▼
  ┌──────────┐
  │  Fleet    │  (Rancher Cluster)
  │  Controller│
  └────┬─────┘
       │ watches & reconciles
       ▼
  ┌──────────┐  ┌──────────┐  ┌──────────┐
  │ Cluster A │  │ Cluster B │  │ Cluster C │
  │ (Fleet    │  │ (Fleet    │  │ (Fleet    │
  │  Agent)   │  │  Agent)   │  │  Agent)   │
  └──────────┘  └──────────┘  └──────────┘
```

### Deploying a GitRepo

```bash
kubectl apply -f fleet-gitrepo.yaml -n fleet-default
```

Fleet will:
1. Clone the Git repository
2. Detect Kubernetes manifests and Helm charts
3. Deploy to all matching target clusters
4. Monitor and reconcile on changes

### Fleet CLI

```bash
# Install Fleet CLI (bundled with Rancher CLI)
# List git repos
fleetctl gitrepo list

# Check bundle status
fleetctl bundle list
```

---

## Cluster Provisioning

Rancher supports provisioning and managing multiple cluster types:

### 1. Custom Clusters (RKE2/K3s on bare metal or VMs)

- Provisioned via Rancher UI or API
- Rancher generates node registration commands
- Nodes register themselves using `rancher-agent`

### 2. Hosted Kubernetes Clusters

| Provider | Rancher Driver |
|---|---|
| Amazon EKS | `eksd` |
| Azure AKS | `aks` |
| Google GKE | `gke` |
| DigitalOcean DOKS | `doks` |
| Linode LKE | `linodek8s` |

### 3. Imported Clusters

Any existing Kubernetes cluster can be imported into Rancher:

1. Navigate to **Cluster Management → Register Existing Cluster**
2. Generate the `kubectl apply` registration manifest
3. Apply on the target cluster
4. Agent connects back to Rancher

See [`cluster-registration.yaml`](./cluster-registration.yaml) for an example registration manifest.

### 4. Downstream RKE2 Clusters via Fleet

Fleet can provision RKE2 clusters on bare metal using custom resources:

```yaml
apiVersion: provisioning.cattle.io/v1
kind: Cluster
metadata:
  name: my-rke2-cluster
  namespace: fleet-default
spec:
  rkeConfig:
    machinePools:
      - name: pool1
        quantity: 3
        machineConfigRef:
          kind: CustomMachineConfig
          name: node-config
```

---

## RBAC and Multi-Tenancy

### Rancher RBAC Model

Rancher extends Kubernetes RBAC with two scopes:

| Scope | Description |
|---|---|
| **Global** | Enterprise-wide permissions (e.g., create users, manage settings) |
| **Cluster** | Per-cluster permissions (e.g., deploy workloads, view pods) |
| **Project** | Per-project (namespace group) permissions |

### Standard Roles

| Role | Permissions |
|---|---|
| `owner` | Full management of cluster/project |
| `member` | Manage workloads (deploy, scale, config) |
| `read-only` | View-only access |
| `admin` | Cluster admin (infrastructure + workloads) |
| `restricted` | Limited access (project-scoped, no secrets) |
| `user` | Cannot manage cluster infrastructure |

### Example: Create a User and Assign Role

```bash
# Using Rancher CLI
rancher login https://rancher.mydomain.com --token TOKEN
rancher clusters create my-cluster
rancher user create --username devuser --password SecretPass
rancher clusters add-member my-cluster --role member --user devuser
```

---

## Backup and Restore

### Rancher Backups (Rancher v2.5+)

Rancher includes a built-in backup operator:

```bash
# Install the Rancher Backup operator
helm repo add rancher-charts https://releases.rancher.com/charts
helm install rancher-backup-crd rancher-charts/rancher-backup-crd -n cattle-resources-system --create-namespace
helm install rancher-backup rancher-charts/rancher-backup -n cattle-resources-system

# Create a backup
kubectl apply -f - <<EOF
apiVersion: resources.cattle.io/v1
kind: Backup
metadata:
  name: my-rancher-backup
spec:
  storageLocation:
    s3:
      bucketName: my-rancher-backups
      region: us-east-1
      folder: rancher/
      credentialSecretName: s3-credentials
EOF

# Restore from backup
kubectl apply -f - <<EOF
apiVersion: resources.cattle.io/v1
kind: Restore
metadata:
  name: my-rancher-restore
spec:
  backupFilename: my-rancher-backup-2026-03-15T10-00-00Z.tar.gz
  storageLocation:
    s3:
      bucketName: my-rancher-backups
      region: us-east-1
      folder: rancher/
      credentialSecretName: s3-credentials
EOF
```

### etcd Snapshots (RKE2)

```bash
# Create an on-demand etcd snapshot
sudo rke2 etcd-snapshot save --name pre-upgrade-snapshot

# List snapshots
sudo ls -la /var/lib/rancher/rke2/server/db/snapshots/

# Restore from snapshot
sudo rke2 server \
  --cluster-reset \
  --cluster-reset-restore-path=/var/lib/rancher/rke2/server/db/snapshots/pre-upgrade-snapshot.tar.gz
```

---

## Monitoring (Prometheus/Grafana)

### Rancher Monitoring App

Rancher provides a built-in monitoring stack based on Prometheus, Grafana, and AlertManager:

```bash
# Install via Rancher UI: Apps & Marketplace → Monitoring
# Or via Helm:
helm repo add rancher-charts https://releases.rancher.com/charts
helm install rancher-monitoring rancher-charts/rancher-monitoring \
  -n cattle-monitoring-system \
  --create-namespace
```

### Key Components

| Component | Purpose |
|---|---|
| **Prometheus** | Metrics collection and storage |
| **Grafana** | Dashboard visualization (pre-built K8s dashboards) |
| **AlertManager** | Alert routing and notification |
| **Prometheus Adapter** | Metrics for HPA (Horizontal Pod Autoscaler) |
| **kube-state-metrics** | Kubernetes object state metrics |
| **Node Exporter** | Host-level metrics |
| **Prometheus Operator** | Manages Prometheus instances as CRDs |

### Custom Dashboards

Grafana dashboards can be added as ConfigMaps in the `cattle-monitoring-system` namespace:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-custom-dashboard
  namespace: cattle-monitoring-system
  labels:
    grafana_dashboard: "1"
data:
  my-dashboard.json: |
    { "dashboard": { ... } }
```

---

## SUSE Virtualization Unification

SUSE is unifying **virtual machines** and **containers** under Rancher:

- **SUSE Manager + Rancher**: Manage both traditional VMs and container workloads
- **KubeVirt on Rancher**: Run VMs alongside containers in the same Kubernetes cluster
- **SUSE Liberty (formerly NeuVector)**: Container security and runtime protection
- **Longhorn**: Distributed block storage for persistent workloads
  ```bash
  # Install Longhorn via Helm
  helm repo add longhorn https://charts.longhorn.io
  helm install longhorn longhorn/longhorn \
    -n longhorn-system \
    --create-namespace
  ```
- **Harvester**: SUSE's hyperconverged infrastructure (HCI) built on KubeVirt

### SUSE AI Ecosystem (2026)

At KubeCon EU 2026, SUSE announced an **open agentic AI ecosystem** within Rancher:

- **AI workload management** alongside traditional apps
- **GPU scheduling and sharing** for inference workloads
- **Model serving** integrations with KServe and similar frameworks
- **Fleet-based AI pipeline delivery** to edge clusters
- **SUSE Rancher Prime AI** bundles for enterprise AI/ML deployments

---

## Troubleshooting

### RKE2 Common Issues

```bash
# Check RKE2 service status
sudo systemctl status rke2-server

# View logs
sudo journalctl -u rke2-server -f

# Check server metrics
/var/lib/rancher/rke2/bin/kubectl get nodes -o wide

# Check etcd health
sudo rke2 etcd-snapshot list

# Check CNI pods
/var/lib/rancher/rke2/bin/kubectl get pods -n kube-system | grep -E 'canal|calico|flannel'

# Restart RKE2
sudo systemctl restart rke2-server
```

### K3s Common Issues

```bash
# Check K3s service status
sudo systemctl status k3s

# View logs
sudo journalctl -u k3s -f

# Check server status
/usr/local/bin/kubectl get nodes

# Restart K3s
sudo systemctl restart k3s

# Uninstall K3s completely
/usr/local/bin/k3s-uninstall.sh
```

### Rancher Common Issues

```bash
# Check Rancher pods
kubectl get pods -n cattle-system

# Check Rancher logs
kubectl logs -n cattle-system -l app=rancher --tail=100 -f

# Check cert-manager
kubectl get pods -n cert-manager
kubectl get challenges -A

# Check ingress controller
kubectl get ingress -n cattle-system

# Restart Rancher
kubectl -n cattle-system rollout restart deploy/rancher

# Reset Rancher admin password
helm upgrade rancher rancher-stable/rancher \
  -n cattle-system \
  --set bootstrapPassword=newpassword

# Check Fleet agents on downstream clusters
kubectl get pods -n cattle-fleet-system -A
```

### Network Troubleshooting

```bash
# Check cluster DNS
kubectl run dns-test --image=busybox:1.36 --rm -it -- nslookup kubernetes.default

# Check CNI configuration
kubectl get pods -n kube-system -l k8s-app=canal

# Test cross-cluster connectivity (Submariner)
subctl diagnose all
```

---

## Files in This Directory

| File | Description |
|---|---|
| [`install-rke2.sh`](./install-rke2.sh) | Automated RKE2 server installation script |
| [`install-k3s.sh`](./install-k3s.sh) | Automated K3s installation script (single + HA) |
| [`install-rancher.sh`](./install-rancher.sh) | Automated Rancher installation via Helm |
| [`rke2-config.yaml`](./rke2-config.yaml) | Example RKE2 configuration with CIS hardening |
| [`helm-values-rancher.yaml`](./helm-values-rancher.yaml) | Example Helm values for Rancher deployment |
| [`fleet-gitrepo.yaml`](./fleet-gitrepo.yaml) | Fleet GitRepo resource example |
| [`rke2-vs-k3s-comparison.md`](./rke2-vs-k3s-comparison.md) | Detailed RKE2 vs K3s comparison |
| [`cluster-registration.yaml`](./cluster-registration.yaml) | Rancher cluster registration manifest |
| [`rancher-cli-cheatsheet.md`](./rancher-cli-cheatsheet.md) | Rancher CLI command reference |

---

## References

- [SUSE Rancher Prime Documentation](https://rancher.com/docs/)
- [RKE2 Documentation](https://docs.rke2.io/)
- [K3s Documentation](https://docs.k3s.io/)
- [Fleet Documentation](https://fleet.rancher.io/)
- [Longhorn Documentation](https://longhorn.io/)
- [SUSE Rancher Prime Product Page](https://www.suse.com/products/rancher/)
- [openSUSE Leap 16](https://get.opensuse.org/leap/)
