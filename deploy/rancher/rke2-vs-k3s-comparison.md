# RKE2 vs K3s — Detailed Comparison

> **Last Updated:** March 2026 | **Platform:** openSUSE Leap 16

## Quick Summary

| | **RKE2** | **K3s** |
|---|---|---|
| **Tagline** | Enterprise Kubernetes for production | Lightweight Kubernetes for edge |
| **Best For** | Data centers, multi-cluster, AI/ML, compliance | Edge, IoT, CI/CD, dev/test, single-node |
| **Package Size** | ~200 MB | ~100 MB |
| **Install on Leap 16** | `sudo zypper install rke2-server` | `sudo zypper install k3s-server` |

---

## Architecture Comparison

### RKE2 Architecture

```
┌─────────────────────────────────────────────────────┐
│                    RKE2 Server                       │
│                                                      │
│  ┌──────────┐  ┌────────────┐  ┌─────────────────┐  │
│  │kube-apiserver│  │kube-scheduler│  │kube-controller │  │
│  └──────────┘  └────────────┘  └─────────────────┘  │
│                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐   │
│  │  etcd    │  │ containerd│  │  Canal CNI       │   │
│  │ (HA built-in)│  │(embedded)│  │(Calico+Flannel) │   │
│  └──────────┘  └──────────┘  └──────────────────┘   │
│                                                      │
│  ┌──────────────────────────────────────────────┐    │
│  │ CIS Hardening Profile (optional)             │    │
│  │ - Audit logging                               │    │
│  │ - Protected kernel defaults                   │    │
│  │ - Pod Security Standards                      │    │
│  └──────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
         │                        │
    ┌────┴────┐             ┌────┴────┐
    │ RKE2    │             │ RKE2    │
    │ Agent   │             │ Agent   │
    │(Worker) │             │(Worker) │
    └─────────┘             └─────────┘
```

### K3s Architecture

```
┌─────────────────────────────────────────┐
│              K3s Server                  │
│  (Single binary, ~100MB)                │
│                                          │
│  ┌──────────┐  ┌─────────────────────┐   │
│  │kube-apiserver│  │kube-scheduler     │   │
│  └──────────┘  └─────────────────────┘   │
│                                          │
│  ┌──────────┐  ┌──────────┐             │
│  │ SQLite   │  │ containerd│             │
│  │(or etcd/ │  │(embedded)│             │
│  │ MySQL/PG)│  └──────────┘             │
│  └──────────┘  ┌──────────┐             │
│                │  Flannel │             │
│                │  CNI     │             │
│                └──────────┘             │
│  ┌──────────┐                           │
│  │ Traefik  │  (bundled ingress)        │
│  └──────────┘                           │
└─────────────────────────────────────────┘
         │
    ┌────┴────┐
    │ K3s     │
    │ Agent   │
    └─────────┘
```

---

## Feature-by-Feature Comparison

### Core Kubernetes

| Feature | **RKE2** | **K3s** |
|---|---|---|
| CNCF Certified | Yes | Yes |
| K8s Version | Latest stable (aligned with upstream) | Latest stable (typically 1–2 minor behind) |
| Single Binary | Yes | Yes |
| Systemd Integration | Yes | Yes |
| Auto-Update | Via SUSE channels / rancher-system-agent | Via SUSE channels / auto-update flag |
| Container Runtime | containerd (only) | containerd (only) |
| kubelet | Embedded | Embedded |
| kube-apiserver | Embedded | Embedded |

### Datastore & HA

| Feature | **RKE2** | **K3s** |
|---|---|---|
| Default Datastore | Embedded etcd | SQLite |
| HA Datastore Options | etcd (native, multi-node) | etcd, MySQL, PostgreSQL |
| HA Quorum | 3 or 5 control plane nodes | 3+ servers (etcd) or external DB |
| Automatic Leader Election | Yes | Yes |
| Data Encryption at Rest | Yes (etcd encryption) | Yes (etcd encryption, if using etcd) |
| Snapshot/Backup | Built-in (`rke2 etcd-snapshot`) | Not built-in (use etcd snapshots or external DB backup) |
| WAL Support | Yes (etcd) | SQLite WAL / etcd WAL |

### Networking

| Feature | **RKE2** | **K3s** |
|---|---|---|
| Default CNI | Canal (Calico + Flannel) | Flannel |
| Alternative CNIs | Calico, Cilium, Multus | Calico, Cilium, WireGuard |
| Network Policies | Yes (Calico) | Yes (Flannel basic, Calico addon) |
| Service LB | kube-proxy + optional MetalLB | Klipper (embedded LB) |
| Ingress Controller | None (install your own) | Traefik (bundled) |
| DNS | CoreDNS | CoreDNS |
| eBPF Support | Via Cilium CNI | Via Cilium CNI |
| Multi-Cluster (Submariner) | Yes (via Rancher) | Yes (via Rancher) |

### Security & Compliance

| Feature | **RKE2** | **K3s** |
|---|---|---|
| CIS Benchmark Profile | Full (cis-1.8, cis-1.9) | Partial (basic profile) |
| Audit Logging | Built-in, configurable | Limited |
| Pod Security Standards | Yes (enforced) | Yes (basic) |
| RBAC | Yes (default-on) | Yes (default-on) |
| Secrets Encryption | Yes (etcd encryption) | Optional |
| Protected Kernel Defaults | Yes (configurable) | Yes (configurable) |
| FIPS Mode | Yes (RKE2 FIPS builds available) | Not standard |
| Image Scanning | Via Rancher + NeuVector | Via Rancher + NeuVector |
| OIDC Integration | Yes | Yes |

### Performance & Resource Usage

| Metric | **RKE2** | **K3s** |
|---|---|---|
| Binary Size | ~200 MB | ~100 MB |
| RAM (idle, single node) | ~500–800 MB | ~200–400 MB |
| RAM (HA, 3 nodes) | ~2–3 GB total | ~1–1.5 GB total |
| CPU (idle) | ~100–200 mCPU | ~50–100 mCPU |
| Startup Time | ~60–120 seconds | ~30–60 seconds |
| Max Cluster Size | Recommended: 1,000+ nodes | Recommended: 100–500 nodes |
| Pod Density | Standard K8s limits | Lower (depends on SQLite/etcd) |

### Ecosystem Integration

| Feature | **RKE2** | **K3s** |
|---|---|---|
| Rancher Management | First-class support | First-class support |
| Fleet GitOps | Full support | Full support |
| Longhorn Storage | Full support | Full support |
| Harvester (HCI) | Yes (compute provider) | Yes (compute provider) |
| Cloud CCM/CSI | Full (external providers) | Limited (in-tree drivers) |
| GPU Support | Yes (NVIDIA device plugin) | Yes (NVIDIA device plugin) |
| Helm 3 | Embedded | Embedded |
| CRDs | All upstream CRDs | Most upstream CRDs (lighter set) |

### openSUSE Leap 16 Packages

| Feature | **RKE2** | **K3s** |
|---|---|---|
| zypper Package | `rke2-server`, `rke2-agent` | `k3s-server`, `k3s-agent` |
| Install Script | Not needed (zypper preferred) | Available (`get.k3s.io`) |
| Uninstall Script | `zypper remove rke2-server` | `k3s-uninstall.sh` |
| Service Name | `rke2-server`, `rke2-agent` | `k3s` |
| Kubeconfig Path | `/var/lib/rancher/rke2/agent/etc/kubeconfig.yaml` | `/etc/rancher/k3s/k3s.yaml` |
| kubectl Path | `/var/lib/rancher/rke2/bin/kubectl` | `/usr/local/bin/kubectl` |
| Config File | `/etc/rancher/rke2/config.yaml` | `/etc/rancher/k3s/config.yaml` |

---

## Use Case Decision Matrix

| Scenario | **RKE2** | **K3s** | **Why** |
|---|---|---|---|
| **Production data center** | ✅ Recommended | ❌ | CIS hardening, etcd HA, full audit logging |
| **AI/ML workloads** | ✅ Recommended | ⚠️ Possible | GPU scheduling, higher pod density, monitoring |
| **Multi-cluster management** | ✅ Recommended | ✅ OK | Both managed equally by Rancher |
| **Edge gateway (retail/branch)** | ⚠️ Possible | ✅ Recommended | Lower resource footprint, single binary |
| **IoT devices (ARM)** | ⚠️ Possible | ✅ Recommended | Minimal resource requirements, ARM-native |
| **CI/CD runners** | ⚠️ Possible | ✅ Recommended | Fast startup, low overhead |
| **Dev/test environment** | ⚠️ Overkill | ✅ Recommended | Quick setup, easy teardown |
| **Homelab / learning** | ⚠️ Possible | ✅ Recommended | Lower resource usage |
| **Air-gapped deployment** | ✅ Recommended | ✅ OK | Both support private registries |
| **Regulated industry** | ✅ Required | ❌ | CIS benchmarks, FIPS, audit logging |
| **PCI-DSS / HIPAA** | ✅ Required | ❌ | Compliance requirements |
| **KubeVirt / VM workloads** | ✅ Recommended | ⚠️ Possible | Heavier workloads need RKE2 resources |
| **GitOps with Fleet** | ✅ OK | ✅ OK | Fleet works identically with both |

---

## Migration Path

### K3s → RKE2

In some cases, you may start with K3s and migrate to RKE2:

1. **Provision RKE2 cluster** alongside K3s
2. **Export K3s workloads**: `kubectl get all --all-namespaces -o yaml > backup.yaml`
3. **Migrate PersistentVolumes** using Longhorn or Velero
4. **Import RKE2 into Rancher**
5. **Switch Fleet targets** to RKE2 cluster
6. **Drain and decommission K3s** cluster

### RKE2 → K3s (Scale-Down)

1. **Use Fleet** to target K3s clusters for lightweight deployments
2. **Keep RKE2** for central/heavy workloads
3. **Use Rancher** to manage both simultaneously

---

## Recommendation for openSUSE Leap 16

| Deployment Type | Recommended Distros | Notes |
|---|---|---|
| **Enterprise production** | RKE2 (3+ nodes) | CIS hardened, etcd HA |
| **Edge / branch offices** | K3s (1–3 nodes) | Lightweight, resilient |
| **Development** | K3s (1 node) | Quick setup, easy teardown |
| **AI/ML clusters** | RKE2 (3+ nodes with GPU) | Higher pod density, monitoring |
| **IoT fleet** | K3s (many 1-node clusters) | Managed via Rancher + Fleet |
| **Mixed (data center + edge)** | RKE2 + K3s via Rancher | Single management plane for all |

---

## References

- [RKE2 Documentation](https://docs.rke2.io/)
- [K3s Documentation](https://docs.k3s.io/)
- [RKE2 vs K3s Official Comparison](https://docs.rke2.io/rke2_vs_k3s)
- [SUSE Rancher Prime](https://www.suse.com/products/rancher/)
- [Fleet GitOps](https://fleet.rancher.io/)
