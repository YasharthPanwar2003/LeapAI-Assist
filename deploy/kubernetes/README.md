# Kubernetes on openSUSE Leap 16

## Overview

openSUSE Leap 16 provides first-class Kubernetes support through multiple deployment options. As SUSE owns Rancher, Leap 16 ships with native packages for **RKE2** (enterprise Kubernetes) and **K3s** (lightweight Kubernetes), alongside the standard `kubernetes-client` for `kubectl` and `helm` for chart management.

This directory contains production-ready Kubernetes manifests, Helm values, and documentation for deploying the SUSE AI Assistant stack.

---

## Table of Contents

1. [Installation Options](#installation-options)
2. [Kubernetes Concepts](#kubernetes-concepts)
3. [kubectl Essential Commands](#kubectl-essential-commands)
4. [YAML Examples](#yaml-examples)
5. [Helm Charts](#helm-charts)
6. [K9s Terminal UI](#k9s-terminal-ui)
7. [SUSE-Specific Notes](#suse-specific-notes)
8. [Files in This Directory](#files-in-this-directory)

---

## Installation Options

### Option 1: kubectl (Client Only)

Install the Kubernetes CLI for managing any cluster:

```bash
# Install kubectl
sudo zypper install kubernetes-client

# Verify installation
kubectl version --client

# Test cluster connectivity
kubectl cluster-info
kubectl get nodes
```

### Option 2: Helm Package Manager

Install Helm for managing Kubernetes charts:

```bash
# Install Helm
sudo zypper install helm

# Verify installation
helm version

# Add common repositories
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add jetstack https://charts.jetstack.io
helm repo update
```

### Option 3: Minikube (Local Development)

Minikube provides a full Kubernetes cluster on your local machine for development:

```bash
# Download and install Minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
rm minikube-linux-amd64

# Start Minikube (using Podman as the container runtime)
minikube start --cpus=4 --memory=8192 --driver=podman

# Verify
kubectl get nodes
minikube status

# Enable addons
minikube addons enable ingress
minikube addons enable metrics-server
minikube addons enable dashboard

# Useful commands
minikube dashboard          # Open web UI
minikube ip                # Get cluster IP
minikube ssh               # SSH into the node
minikube stop              # Stop cluster
minikube delete            # Delete cluster
```

### Option 4: K3s (Lightweight Production)

K3s is a lightweight Kubernetes distribution by SUSE/Rancher, ideal for edge, IoT, and resource-constrained environments:

```bash
# Install K3s server (single-node or first control plane node)
sudo zypper install k3s-server
sudo systemctl enable --now k3s

# Verify
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A

# Get kubeconfig
sudo cat /etc/rancher/k3s/k3s.yaml

# Copy kubeconfig to user directory
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# Join worker nodes
sudo zypper install k3s-agent
# Then configure the agent to join the server

# Install Helm via K3s bundled script (alternative to zypper)
sudo k3s kubectl apply -f https://github.com/k3s-io/helm/releases/download/v3.17.3/helm-install.yaml

# Uninstall
sudo zypper remove k3s-server
sudo rm -rf /var/lib/rancher/k3s
```

### Option 5: RKE2 (Enterprise Production)

RKE2 (Rancher Kubernetes Engine 2) is SUSE's enterprise-grade Kubernetes distribution with full CNCF certification:

```bash
# Install RKE2 server (control plane)
sudo zypper install rke2-server
sudo systemctl enable --now rke2-server

# Verify
sudo systemctl status rke2-server

# Access kubeconfig
sudo cat /var/lib/rancher/rke2/agent/etc/kubeconfig.yaml

# Copy kubeconfig to user directory
mkdir -p ~/.kube
sudo cp /var/lib/rancher/rke2/agent/etc/kubeconfig.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
export KUBECONFIG=~/.kube/config

# Check cluster status
kubectl get nodes
kubectl get pods -A

# Join worker nodes
sudo zypper install rke2-agent
# Configure /etc/rancher/rke2/config.yaml with server URL and token:
#   server: https://<server-ip>:9345
#   token: <token-from-server>

# Get node token from server
sudo cat /var/lib/rancher/rke2/server/node-token

# Install cert-manager (required for ingress TLS)
sudo zypper install rke2-latest
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --set replicaCount=1

# Uninstall
sudo zypper remove rke2-server
sudo rm -rf /var/lib/rancher/rke2
```

### Quick Comparison

| Feature | Minikube | K3s | RKE2 |
|---------|----------|-----|------|
| Use Case | Local dev | Edge/lightweight prod | Enterprise production |
| Binary Size | ~200MB | ~100MB | ~300MB |
| Memory | 2GB+ | 512MB+ | 2GB+ |
| etcd | SQLite (embedded) | SQLite/MariaDB/etcd | etcd (native) |
| Container Runtime | Docker/Podman | containerd | containerd |
| CNCF Certified | Yes | Yes | Yes |
| HA Support | No | Yes | Yes |
| CIS Benchmark | No | Yes | Yes |
| Managed By | Community | SUSE/Rancher | SUSE/Rancher |
| Package | Manual install | `k3s-server` | `rke2-server` |

---

## Kubernetes Concepts

### Core Resource Types

| Resource | Short Name | Description |
|----------|-----------|-------------|
| **Pod** | `po` | Smallest deployable unit; one or more containers sharing network/storage |
| **Deployment** | `deploy` | Declarative updates for Pods and ReplicaSets |
| **Service** | `svc` | Network abstraction exposing Pods via stable IP/DNS |
| **ConfigMap** | `cm` | External configuration data as key-value pairs |
| **Secret** | `secret` | Sensitive data (base64-encoded): passwords, tokens, keys |
| **Ingress** | `ing` | HTTP/HTTPS routing rules (Layer 7 load balancing) |
| **PersistentVolumeClaim** | `pvc` | Request for storage by a user |
| **PersistentVolume** | `pv` | Actual storage provisioned in the cluster |
| **Namespace** | `ns` | Logical partition within a single cluster |
| **Node** | `no` | Worker machine (VM or physical) |
| **ReplicaSet** | `rs` | Ensures a specified number of Pod replicas |
| **StatefulSet** | `sts` | Stateful application management (databases, queues) |
| **DaemonSet** | `ds` | Runs a Pod on every Node |
| **Job** | `job` | Runs a Pod to completion |
| **CronJob** | `cj` | Runs Jobs on a schedule |
| **ServiceAccount** | `sa` | Identity for processes running in a Pod |
| **Role** | `role` | Namespace-scoped permissions |
| **RoleBinding** | `rb` | Binds a Role to subjects (users, groups, SAs) |
| **ClusterRole** | `cr` | Cluster-wide permissions |
| **ClusterRoleBinding** | `crb` | Binds a ClusterRole to subjects |
| **NetworkPolicy** | `netpol` | Controls traffic flow between Pods |
| **HorizontalPodAutoscaler** | `hpa` | Auto-scales Pods based on metrics |

### How Resources Relate

```
Namespace (isolation boundary)
  |
  +-- Deployment (manages Pods)
  |     |
  |     +-- ReplicaSet (maintains replica count)
  |           |
  |           +-- Pod (running container)
  |                 |
  |                 +-- Container (your app)
  |                 +-- Volume (storage mount)
  |                 +-- ConfigMap (config files / env vars)
  |                 +-- Secret (sensitive data)
  |
  +-- Service (stable network endpoint for Pods)
  |     |
  |     +-- Endpoints (Pod IPs behind the Service)
  |
  +-- Ingress (external HTTP/HTTPS access)
  |     |
  |     +-- Routes traffic to Services
  |
  +-- PVC (storage claim)
  |     |
  |     +-- PV (actual storage backend)
  |
  +-- ServiceAccount (Pod identity)
  +-- Role + RoleBinding (permissions)
```

---

## kubectl Essential Commands

### Cluster Management

```bash
# Cluster information
kubectl cluster-info
kubectl version
kubectl api-resources                         # List all resource types
kubectl api-versions                          # List all API versions

# Node management
kubectl get nodes
kubectl describe node <node-name>
kubectl cordon <node-name>                    # Mark node unschedulable
kubectl uncordon <node-name>                  # Mark node schedulable
kubectl drain <node-name>                     # Evict pods and cordon
kubectl taint node <node-name> key=value:NoSchedule

# Component statuses
kubectl get componentstatuses                 # Deprecated in 1.19+
kubectl get --raw='/readyz?verbose'           # Health check
```

### Namespace Operations

```bash
kubectl create namespace <name>
kubectl get namespaces
kubectl get ns                                # Short form
kubectl describe namespace <name>
kubectl delete namespace <name>
kubectl config set-context --current --namespace=<name>  # Set default ns
```

### Pod Operations

```bash
kubectl get pods
kubectl get pods -o wide                      # Show node and IP
kubectl get pods -w                           # Watch for changes
kubectl get pods --all-namespaces
kubectl get pods -n <namespace>
kubectl get pods --sort-by='.status.startTime'
kubectl get pods --field-selector=status.phase=Running

kubectl describe pod <pod-name>
kubectl logs <pod-name>
kubectl logs <pod-name> -c <container>        # Specific container
kubectl logs <pod-name> --tail=100
kubectl logs <pod-name> --since=1h
kubectl logs <pod-name> -f                    # Follow logs
kubectl logs <pod-name> --previous            # Previous crashed container

kubectl exec -it <pod-name> -- /bin/sh        # Shell into pod
kubectl exec <pod-name> -- ls /app            # Run command in pod
kubectl port-forward <pod-name> 8080:80       # Forward port
kubectl cp <pod-name>:/path/file ./local-file # Copy from pod
kubectl cp ./local-file <pod-name>:/path/file # Copy to pod

kubectl delete pod <pod-name>
kubectl delete pod <pod-name> --force --grace-period=0  # Force delete
```

### Deployment Operations

```bash
kubectl create deployment <name> --image=<image> --replicas=3
kubectl get deployments
kubectl get deploy                             # Short form
kubectl describe deployment <name>
kubectl scale deployment <name> --replicas=5
kubectl autoscale deployment <name> --min=2 --max=10 --cpu-percent=80

kubectl rollout status deployment/<name>
kubectl rollout history deployment/<name>
kubectl rollout history deployment/<name> --revision=2
kubectl rollout undo deployment/<name>          # Rollback to previous
kubectl rollout undo deployment/<name> --to-revision=2
kubectl rollout restart deployment/<name>       # Restart all pods
kubectl rollout pause deployment/<name>
kubectl rollout resume deployment/<name>

kubectl set image deployment/<name> <container>=<image>:<tag>
kubectl set resources deployment/<name> -c <container> --limits=cpu=200m,memory=512Mi

kubectl delete deployment <name>
```

### Service Operations

```bash
kubectl expose deployment <name> --port=80 --target-port=8080 --type=ClusterIP
kubectl expose deployment <name> --port=80 --type=NodePort
kubectl expose deployment <name> --port=80 --type=LoadBalancer

kubectl get services
kubectl get svc                                # Short form
kubectl describe svc <name>
kubectl get endpoints <svc-name>

kubectl delete svc <name>
```

### ConfigMap & Secret Operations

```bash
# ConfigMaps
kubectl create configmap <name> --from-literal=key1=value1
kubectl create configmap <name> --from-file=config.yaml
kubectl create configmap <name> --from-env-file=.env
kubectl get configmaps
kubectl get cm                                 # Short form
kubectl describe cm <name>
kubectl get cm <name> -o yaml

# Secrets
kubectl create secret generic <name> --from-literal=password=secret123
kubectl create secret generic <name> --from-file=ssh-key=~/.ssh/id_rsa
kubectl create secret docker-registry <name> --docker-server=<server> --docker-username=<user> --docker-password=<pass>
kubectl create secret tls <name> --cert=tls.crt --key=tls.key
kubectl get secrets
kubectl describe secret <name>
kubectl get secret <name> -o jsonpath='{.data.password}' | base64 -d
```

### Ingress Operations

```bash
kubectl get ingress
kubectl get ing                                # Short form
kubectl describe ing <name>
kubectl delete ing <name>
```

### Persistent Volume Operations

```bash
kubectl get pv
kubectl get pvc
kubectl describe pvc <name>
kubectl describe pv <name>
kubectl delete pvc <name>                      # Also deletes PV if reclaim policy is Delete
kubectl patch pv <pv-name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```

### RBAC Operations

```bash
kubectl get serviceaccounts
kubectl get sa
kubectl get roles
kubectl get rolebindings
kubectl get clusterroles
kubectl get clusterrolebindings
kubectl describe role <name> -n <namespace>
kubectl describe clusterrole <name>
kubectl auth can-i list pods --as=system:serviceaccount:<ns>:<sa>
kubectl auth can-i create deployments --as=system:serviceaccount:<ns>:<sa>
kubectl auth reconcile -f rbac.yaml
```

### Debugging & Troubleshooting

```bash
kubectl get events --sort-by='.lastTimestamp'
kubectl get events -w
kubectl describe pod <pod-name>                # Check events at the bottom
kubectl get pod <pod-name> -o yaml
kubectl get pod <pod-name> -o jsonpath='{.status.phase}'
kubectl get pod <pod-name> -o jsonpath='{.status.containerStatuses[*].ready}'

# Resource usage
kubectl top nodes
kubectl top pods
kubectl top pods --containers
kubectl top pods -l app=<app-label>

# Debug containers
kubectl run debug --image=busybox -it --rm --restart=Never
kubectl debug <pod-name> -it --image=nicolaka/netshoot
```

### Apply & Manage Manifests

```bash
kubectl apply -f file.yaml
kubectl apply -f directory/
kubectl apply -f https://url/manifest.yaml
kubectl apply -f file.yaml --dry-run=client     # Validate without applying
kubectl apply -f file.yaml --dry-run=client -o yaml  # Print rendered YAML
kubectl apply -f file.yaml --server-side        # Server-side apply

kubectl delete -f file.yaml
kubectl delete -f directory/
kubectl replace -f file.yaml
kubectl patch deployment <name> -p '{"spec":{"replicas":3}}'

kubectl diff -f file.yaml                      # Show differences (requires kubectl diff plugin)
```

### Label & Annotation Operations

```bash
kubectl label pod <pod-name> env=prod
kubectl label pod <pod-name> env-               # Remove label
kubectl label pod <pod-name> env=staging --overwrite

kubectl annotate pod <pod-name> description="production pod"
kubectl annotate pod <pod-name> description-

kubectl get pods -l app=ai-assistant
kubectl get pods -l 'env in (prod,staging)'
kubectl get pods -l 'tier notin (frontend)'
kubectl get all -l app=ai-assistant             # All resources with label
```

### Output Formatting

```bash
kubectl get pods -o yaml
kubectl get pods -o json
kubectl get pods -o wide
kubectl get pods -o name
kubectl get pods -o custom-columns=NAME:.metadata.name,STATUS:.status.phase
kubectl get pods -o jsonpath='{.items[*].metadata.name}'
kubectl get pods -o go-template='{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}'
```

---

## YAML Examples

### Namespace

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ai-assistant
  labels:
    app.kubernetes.io/name: ai-assistant
    app.kubernetes.io/part-of: suse-ai-deploy
```

### Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: ai-assistant-pod
  namespace: ai-assistant
  labels:
    app: ai-assistant
spec:
  containers:
    - name: ai-assistant
      image: registry.suse.com/ai-assistant:latest
      ports:
        - containerPort: 8000
      env:
        - name: APP_ENV
          value: "production"
      resources:
        requests:
          cpu: "100m"
          memory: "256Mi"
        limits:
          cpu: "500m"
          memory: "512Mi"
```

### Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ai-assistant
  namespace: ai-assistant
  labels:
    app: ai-assistant
spec:
  replicas: 3
  selector:
    matchLabels:
      app: ai-assistant
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: ai-assistant
    spec:
      containers:
        - name: ai-assistant
          image: registry.suse.com/ai-assistant:1.0.0
          ports:
            - containerPort: 8000
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /ready
              port: 8000
            initialDelaySeconds: 5
            periodSeconds: 5
          resources:
            requests:
              cpu: "250m"
              memory: "512Mi"
            limits:
              cpu: "1000m"
              memory: "1Gi"
          volumeMounts:
            - name: config
              mountPath: /app/config
            - name: data
              mountPath: /app/data
      volumes:
        - name: config
          configMap:
            name: ai-assistant-config
        - name: data
          persistentVolumeClaim:
            claimName: ai-assistant-data
```

### Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ai-assistant
  namespace: ai-assistant
spec:
  type: ClusterIP
  selector:
    app: ai-assistant
  ports:
    - port: 80
      targetPort: 8000
      protocol: TCP
---
apiVersion: v1
kind: Service
metadata:
  name: ai-assistant-external
  namespace: ai-assistant
spec:
  type: NodePort
  selector:
    app: ai-assistant
  ports:
    - port: 80
      targetPort: 8000
      nodePort: 30080
```

### ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ai-assistant-config
  namespace: ai-assistant
data:
  APP_ENV: "production"
  LOG_LEVEL: "info"
  MODEL_PATH: "/app/models"
  config.yaml: |
    server:
      host: 0.0.0.0
      port: 8000
    llm:
      provider: ollama
      model: llama3.1
    database:
      host: postgres-service
      port: 5432
```

### Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ai-assistant-secret
  namespace: ai-assistant
type: Opaque
data:
  # Values must be base64 encoded
  # echo -n 'my-password' | base64
  DATABASE_PASSWORD: bXktcGFzc3dvcmQ=
  API_KEY: YWJjZGVmMTIzNDU2
---
# TLS Secret
apiVersion: v1
kind: Secret
metadata:
  name: ai-assistant-tls
  namespace: ai-assistant
type: kubernetes.io/tls
data:
  tls.crt: <base64-encoded-cert>
  tls.key: <base64-encoded-key>
```

### PersistentVolumeClaim

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ai-assistant-data
  namespace: ai-assistant
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: local-path   # Default for K3s, use 'longhorn' for RKE2
```

### Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ai-assistant
  namespace: ai-assistant
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - ai.example.com
      secretName: ai-assistant-tls
  rules:
    - host: ai.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ai-assistant
                port:
                  number: 80
```

### RBAC

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ai-assistant-sa
  namespace: ai-assistant
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ai-assistant-role
  namespace: ai-assistant
rules:
  - apiGroups: [""]
    resources: ["configmaps", "secrets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ai-assistant-binding
  namespace: ai-assistant
subjects:
  - kind: ServiceAccount
    name: ai-assistant-sa
    namespace: ai-assistant
roleRef:
  kind: Role
  name: ai-assistant-role
  apiGroup: rbac.authorization.k8s.io
```

---

## Helm Charts

### Basic Usage

```bash
# Search for charts
helm search repo nginx
helm search hub nginx

# Install a chart
helm install my-release bitnami/nginx -n default

# Install with values file
helm install my-release bitnami/nginx -n ai-assistant -f values.yaml

# Install with set values
helm install my-release bitnami/nginx \
  --set replicaCount=3 \
  --set service.type=ClusterIP

# Dry-run (validate)
helm install my-release bitnami/nginx --dry-run --debug

# List releases
helm list
helm list -n ai-assistant
helm list -a                    # Show all (including deleted)

# Status
helm status my-release

# Upgrade
helm upgrade my-release bitnami/nginx -f updated-values.yaml
helm upgrade --install my-release bitnami/nginx -f values.yaml  # Install or upgrade

# Rollback
helm rollback my-release 1
helm rollback my-release 1       # Rollback to revision 1

# History
helm history my-release

# Uninstall
helm uninstall my-release

# Show values
helm show values bitnami/nginx > default-values.yaml
helm get values my-release       # Show current values
helm get all my-release          # Show all info

# Template (render YAML without installing)
helm template my-release ./chart -f values.yaml > rendered.yaml

# Package a chart
helm package ./chart
```

### Managing Repositories

```bash
# Add repositories
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add jetstack https://charts.jetstack.io
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update
helm repo list

# Remove a repository
helm repo remove bitnami
```

### Creating a Chart

```bash
# Create a new chart
helm create my-chart

# Chart structure
my-chart/
  Chart.yaml          # Chart metadata
  values.yaml         # Default values
  templates/          # Template files
    deployment.yaml
    service.yaml
    ingress.yaml
    _helpers.tpl      # Template helpers
    NOTES.txt         # Post-install notes
  charts/             # Dependency charts

# Lint the chart
helm lint my-chart

# Debug templates
helm template my-release my-chart --debug
```

---

## K9s Terminal UI

[K9s](https://k9scli.io/) is a terminal UI for Kubernetes that provides an interactive, keyboard-driven interface:

```bash
# Install K9s
# Download from GitHub releases
curl -sS https://webinstall.dev/k9s | bash

# Or install via Go (if Go is available)
go install github.com/derailed/k9s@latest

# Launch K9s
k9s

# Launch with specific namespace
k9s -n ai-assistant

# Launch with specific context
k9s --context my-context

# Key bindings:
# :<resource>      Jump to resource (e.g., :pods, :deploy, :svc)
# /<filter>       Filter resources
# d               Describe resource
# l               Show logs
# e               Edit YAML
# y               Show YAML
# s               Shell into pod
# a               Show resource aliases
# ?               Help
# q               Quit
# :quit           Quit
# ctrl+a          Alias help
# :watch          Toggle auto-refresh
# x               Toggle error view
```

---

## SUSE-Specific Notes

### Rancher Integration

SUSE owns Rancher, making RKE2 and K3s the recommended Kubernetes distributions for openSUSE Leap 16:

- **RKE2** is CNCF-certified, passes CIS benchmarks, and includes all Kubernetes features. Use for production workloads.
- **K3s** is also CNCF-certified but strips out legacy/alpha features for a lighter footprint. Use for edge, IoT, and smaller deployments.
- Both ship as native zypper packages on Leap 16, ensuring easy installation and updates.

### Container Runtime

- RKE2 and K3s both use **containerd** as the container runtime.
- For Minikube on openSUSE, **Podman** is recommended as the driver: `minikube start --driver=podman`
- Podman is rootless by default and is the preferred container tool on openSUSE.

### Storage Classes

| Distribution | Default StorageClass |
|-------------|---------------------|
| K3s | `local-path` (Rancher local-path-provisioner) |
| RKE2 | No default (install Longhorn or use cloud provider) |
| Minikube | `standard` (hostPath) |

```bash
# Check available storage classes
kubectl get storageclasses

# Install Longhorn for RKE2 (recommended)
helm repo add longhorn https://charts.longhorn.io
helm install longhorn longhorn/longhorn -n longhorn-system --create-namespace

# Set default storage class
kubectl patch storageclass longhorn -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### Ingress Controller

```bash
# K3s bundles Traefik by default
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik

# For RKE2, install NGINX Ingress Controller
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.publishService.enabled=true

# Or use the RKE2 bundled NGINX HelmChart
# Edit /etc/rancher/rke2/config.yaml:
#   helm:
#     defaultChart:
#       repo: https://kubernetes.github.io/ingress-nginx
#       chartName: ingress-nginx
#       chartVersion: 4.x.x
```

### Networking

- K3s uses **Canal** (Calico + Flannel) by default.
- RKE2 uses **Canal** by default, supports Calico, Cilium, and others.
- Network policies are supported out of the box with Canal.

### Cert-Manager for TLS

```bash
# Install cert-manager
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --set replicaCount=1

# Create ClusterIssuer for Let's Encrypt
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
EOF
```

### Useful SUSE/Rancher Resources

- [RKE2 Documentation](https://docs.rke2.io/)
- [K3s Documentation](https://docs.k3s.io/)
- [Rancher Documentation](https://rancher.com/docs/)
- [SUSE Rancher](https://www.suse.com/products/suse-rancher/)
- [openSUSE Leap 16](https://get.opensuse.org/leap/)

---

## Files in This Directory

| File | Description |
|------|-------------|
| `README.md` | This comprehensive guide |
| `k8s-namespace.yaml` | Namespace definition |
| `k8s-deployment.yaml` | AI assistant Deployment (3 replicas, probes, resources) |
| `k8s-service.yaml` | ClusterIP + NodePort services |
| `k8s-configmap.yaml` | Application configuration |
| `k8s-pvc.yaml` | PersistentVolumeClaim for data storage |
| `k8s-ingress.yaml` | Ingress with TLS |
| `k8s-rbac.yaml` | ServiceAccount, Role, RoleBinding |
| `helm-values.yaml` | Example Helm values file |
| `kubectl-cheatsheet.md` | Quick reference kubectl commands |

---

## Quick Start

```bash
# 1. Set up cluster (choose one)
sudo zypper install k3s-server && sudo systemctl enable --now k3s   # K3s
sudo zypper install rke2-server && sudo systemctl enable --now rke2-server  # RKE2
minikube start --driver=podman                                       # Dev

# 2. Install kubectl and Helm
sudo zypper install kubernetes-client helm

# 3. Deploy the AI assistant
kubectl apply -f k8s-namespace.yaml
kubectl apply -f k8s-configmap.yaml
kubectl apply -f k8s-pvc.yaml
kubectl apply -f k8s-rbac.yaml
kubectl apply -f k8s-deployment.yaml
kubectl apply -f k8s-service.yaml
kubectl apply -f k8s-ingress.yaml

# 4. Verify
kubectl get all -n ai-assistant
kubectl logs -f deployment/ai-assistant -n ai-assistant
```
