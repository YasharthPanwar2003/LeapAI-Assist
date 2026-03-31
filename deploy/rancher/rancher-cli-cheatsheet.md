# Rancher CLI Cheatsheet

> **Last Updated:** March 2026 | **Rancher Version:** 2.10+ | **CLI Version:** 2.8+

## Table of Contents

- [Installation](#installation)
- [Login & Authentication](#login--authentication)
- [Cluster Management](#cluster-management)
- [Node Management](#node-management)
- [Project & Namespace Management](#project--namespace-management)
- [User & RBAC Management](#user--rbac-management)
- [App & Marketplace](#app--marketplace)
- [Fleet GitOps](#fleet-gitops)
- [Kubeconfig & Context Switching](#kubeconfig--context-switching)
- [Secrets Management](#secrets-management)
- [Backup & Restore](#backup--restore)
- [Troubleshooting & Debug](#troubleshooting--debug)

---

## Installation

```bash
# Install Rancher CLI (Linux)
# Download from: https://github.com/rancher/cli/releases
wget https://github.com/rancher/cli/releases/download/v2.8.0/rancher-linux-amd64-v2.8.0.tar.gz
tar -xzf rancher-linux-amd64-v2.8.0.tar.gz
sudo mv rancher-v2.8.0/rancher /usr/local/bin/
sudo chmod +x /usr/local/bin/rancher

# Install via zypper (if available)
sudo zypper install rancher-cli

# Verify installation
rancher --version
```

---

## Login & Authentication

```bash
# Login with token (recommended)
rancher login https://rancher.mydomain.com --token "token-xxxxx"

# Login with username/password (interactive)
rancher login https://rancher.mydomain.com
# Enter username and password when prompted

# Login and save context
rancher login https://rancher.mydomain.com --token "token-xxxxx" --context my-rancher

# Login skipping TLS verification (not recommended for production)
rancher login https://rancher.mydomain.com --token "token-xxxxx" --insecure

# Logout
rancher logout

# Check current context
rancher context current

# List available contexts
rancher context ls
```

---

## Cluster Management

### List & Inspect Clusters

```bash
# List all clusters
rancher clusters ls

# Show cluster details
rancher clusters ls --format yaml

# Get cluster info by name/ID
rancher clusters show <cluster-name>

# Watch cluster status
rancher clusters ls --watch
```

### Create Clusters

```bash
# Create a new RKE2 cluster
rancher clusters create my-rke2-cluster \
  --provider rke2 \
  --nodes 3 \
  --node-pool "pool1:3"

# Create an imported/registered cluster
rancher clusters import my-imported-cluster

# Create an EKS cluster
rancher clusters create my-eks-cluster \
  --provider eks \
  --region us-east-1 \
  --node-count 3

# Create an AKS cluster
rancher clusters create my-aks-cluster \
  --provider aks \
  --region eastus \
  --node-count 3

# Create a GKE cluster
rancher clusters create my-gke-cluster \
  --provider gke \
  --region us-central1 \
  --project my-gcp-project
```

### Delete Clusters

```bash
# Delete a cluster
rancher clusters delete <cluster-name>

# Force delete (if stuck in removing state)
rancher clusters delete <cluster-name> --force
```

### Cluster Operations

```bash
# Run kubectl commands against a cluster via Rancher
rancher kubectl <cluster-name> get nodes
rancher kubectl <cluster-name> get pods -A

# Get cluster kubeconfig
rancher clusters kubeconfig <cluster-name>

# Rotate cluster certificates
rancher clusters rotate-certs <cluster-name>

# Enable monitoring on a cluster
rancher clusters enable-monitoring <cluster-name>
```

---

## Node Management

```bash
# List nodes in a cluster
rancher nodes ls --cluster <cluster-name>

# Show node details
rancher nodes show <node-id> --cluster <cluster-name>

# Cordon a node (no new pods scheduled)
rancher nodes cordon <node-id> --cluster <cluster-name>

# Uncordon a node
rancher nodes uncordon <node-id> --cluster <cluster-name>

# Drain a node (evict pods)
rancher nodes drain <node-id> --cluster <cluster-name>

# Delete a node
rancher nodes delete <node-id> --cluster <cluster-name>

# Add node labels
rancher nodes labels add <node-id> --cluster <cluster-name> \
  --label "environment=production" \
  --label "node-role=worker"

# Remove node labels
rancher nodes labels remove <node-id> --cluster <cluster-name> \
  --label "environment"
```

---

## Project & Namespace Management

```bash
# List projects in a cluster
rancher projects ls --cluster <cluster-name>

# Create a project
rancher projects create my-project --cluster <cluster-name>

# Show project details
rancher projects show <project-id> --cluster <cluster-name>

# Delete a project
rancher projects delete <project-id> --cluster <cluster-name>

# List namespaces
rancher namespaces ls --cluster <cluster-name>

# Move namespace to a project
rancher namespaces move <namespace-name> --project <project-id> --cluster <cluster-name>
```

---

## User & RBAC Management

### Users

```bash
# Create a user
rancher users create \
  --username devuser \
  --password "SecurePassword123!" \
  --name "Developer User" \
  --email "devuser@example.com"

# List users
rancher users ls

# Show user details
rancher users show <user-id>

# Update user
rancher users update <user-id> --name "New Name"

# Delete user
rancher users delete <user-id>
```

### Roles & Permissions

```bash
# List standard roles
rancher roles ls

# Show role details
rancher roles show cluster-owner
rancher roles show project-member

# Add member to cluster
rancher clusters add-member <cluster-name> \
  --role cluster-owner \
  --user devuser

# Add member to project
rancher projects add-member <project-id> --cluster <cluster-name> \
  --role project-member \
  --user devuser

# Remove member from cluster
rancher clusters remove-member <cluster-name> \
  --user devuser

# Create custom role
rancher roles create \
  --name "readonly-without-secrets" \
  --description "Read-only access, no secrets" \
  --rules "resources:[*];verbs:[get,list,watch];apiGroups:[*]"

# List role templates
rancher roletemplates ls
```

### Tokens

```bash
# Create API token
rancher tokens create \
  --description "CI/CD token" \
  --ttl 720h

# List tokens
rancher tokens ls

# Revoke token
rancher tokens delete <token-id>
```

---

## App & Marketplace

```bash
# List available Helm charts / Rancher apps
rancher app ls --cluster <cluster-name>

# Search for apps
rancher app search monitoring --cluster <cluster-name>

# Install an app
rancher app install monitoring rancher-monitoring \
  --cluster <cluster-name> \
  --version 102.0.0+up19.0.3

# Install with custom values
rancher app install monitoring rancher-monitoring \
  --cluster <cluster-name> \
  --values my-monitoring-values.yaml

# Upgrade an app
rancher app upgrade monitoring rancher-monitoring \
  --cluster <cluster-name> \
  --version 103.0.0+up20.0.0

# Rollback an app
rancher app rollback monitoring --revision 2 --cluster <cluster-name>

# List installed apps
rancher app ls --cluster <cluster-name>

# Show app details
rancher app show monitoring --cluster <cluster-name>

# Get app notes
rancher app notes monitoring --cluster <cluster-name>

# Uninstall an app
rancher app uninstall monitoring --cluster <cluster-name>
```

---

## Fleet GitOps

```bash
# NOTE: Fleet operations are typically done via kubectl, not rancher CLI.
# The Rancher UI provides the best Fleet management experience.

# List Fleet GitRepos (via kubectl)
kubectl get gitrepos -n fleet-default

# Show GitRepo status
kubectl describe gitrepo <name> -n fleet-default

# Check bundle deployment status
kubectl get bundles -n fleet-default

# Force reconciliation
kubectl annotate gitrepo <name> -n fleet-default \
  fleet.cattle.io/reconcile-start=2026-03-15T10:00:00Z \
  --overwrite

# Delete a GitRepo
kubectl delete gitrepo <name> -n fleet-default

# List Fleet clusters
kubectl get clusters.fleet.cattle.io

# List Fleet bundles across all namespaces
kubectl get bundles.fleet.cattle.io -A
```

---

## Kubeconfig & Context Switching

```bash
# Get kubeconfig for a cluster
rancher clusters kubeconfig <cluster-name> > ~/.kube/cluster-config

# Export kubeconfig for downstream cluster
export KUBECONFIG=~/.kube/cluster-config

# Switch contexts (using kubectl)
kubectl config use-context <context-name>
kubectl config get-contexts

# Merge rancher kubeconfig with existing
rancher clusters kubeconfig <cluster-name> | \
  KUBECONFIG=~/.kube/config:~/.kube/rancher-config kubectl config view --flatten > merged-config
```

---

## Secrets Management

```bash
# Create a secret (via rancher kubectl)
rancher kubectl <cluster-name> create secret generic my-secret \
  --from-literal=username=admin \
  --from-literal=password=SecretPass

# List secrets
rancher kubectl <cluster-name> get secrets -n <namespace>

# Create a Docker registry secret
rancher kubectl <cluster-name> create secret docker-registry registry-secret \
  --docker-server=registry.example.com \
  --docker-username=user \
  --docker-password=pass

# Create a TLS secret
rancher kubectl <cluster-name> create secret tls my-tls-secret \
  --cert=cert.pem \
  --key=key.pem
```

---

## Backup & Restore

```bash
# Rancher backup operations are done via kubectl

# List backups
kubectl get backups.resources.cattle.io

# Create a backup
kubectl apply -f - <<EOF
apiVersion: resources.cattle.io/v1
kind: Backup
metadata:
  name: daily-backup-$(date +%Y%m%d)
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
  name: restore-$(date +%Y%m%d)
spec:
  backupFilename: daily-backup-20260315.tar.gz
  storageLocation:
    s3:
      bucketName: my-rancher-backups
      region: us-east-1
      credentialSecretName: s3-credentials
EOF

# RKE2 etcd snapshots (run on RKE2 server nodes)
sudo rke2 etcd-snapshot save --name my-snapshot
sudo rke2 etcd-snapshot list
```

---

## Troubleshooting & Debug

```bash
# Check Rancher server health
rancher clusters ls  # If this works, Rancher is responsive

# Get cluster events
rancher kubectl <cluster-name> get events --sort-by='.lastTimestamp'

# Check cluster agent logs
rancher kubectl <cluster-name> logs -n cattle-system -l app=cattle-cluster-agent --tail=100

# Check specific pod logs
rancher kubectl <cluster-name> logs -n <namespace> <pod-name>

# Describe a resource
rancher kubectl <cluster-name> describe node <node-name>
rancher kubectl <cluster-name> describe pod <pod-name> -n <namespace>

# Check cluster conditions
rancher kubectl <cluster-name> get nodes -o wide
rancher kubectl <cluster-name> get componentstatuses

# Shell into a pod
rancher kubectl <cluster-name> exec -it <pod-name> -n <namespace> -- /bin/sh

# Port-forward a service
rancher kubectl <cluster-name> port-forward svc/<service-name> <local-port>:<remote-port> -n <namespace>

# Check Rancher server logs (direct on Rancher cluster)
kubectl logs -n cattle-system -l app=rancher --tail=200 -f

# Check cert-manager
kubectl get challenges -A
kubectl get certificates -A

# Rancher API calls (raw)
curl -sk -H "Authorization: Bearer <token>" \
  "https://rancher.mydomain.com/v3/clusters"
```

---

## Quick Reference: Common Patterns

```bash
# === DAILY OPERATIONS ===

# Check all cluster health
rancher clusters ls --format table

# Deploy workload via Helm
rancher app install my-app my-chart \
  --cluster production \
  --namespace default \
  --values values.yaml

# Check Fleet status
kubectl get gitrepos,clusters.fleet.cattle.io,bundles.fleet.cattle.io -A

# === ON-CALL TROUBLESHOOTING ===

# Quick cluster health check
rancher kubectl <cluster-name> get nodes
rancher kubectl <cluster-name> top nodes
rancher kubectl <cluster-name> top pods -A | sort -k3 -n -r | head -20

# Find failing pods
rancher kubectl <cluster-name> get pods -A | grep -E 'Error|CrashLoop|Pending|ImagePull'

# Quick backup before changes
sudo rke2 etcd-snapshot save --name pre-maintenance-$(date +%Y%m%d-%H%M%S)
```

---

## References

- [Rancher CLI GitHub](https://github.com/rancher/cli)
- [Rancher API Docs](https://rancher.com/docs/rancher/v2.6/en/api/)
- [Rancher CLI Reference](https://rancher.com/docs/rancher/v2.6/en/cli/)
- [Fleet Documentation](https://fleet.rancher.io/)
