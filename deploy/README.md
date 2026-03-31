# openSUSE AI Assistant - Deploy

**Local SLM (Small Language Model) with RAG for openSUSE system onboarding.**

Run AI-powered chat assistance directly on your openSUSE Leap 16 machine — no cloud, no data leaving your system. Designed for JeOS first-boot onboarding, desktop help, and server administration.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    openSUSE AI Assistant                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐   ┌──────────────┐   ┌─────────────────────┐  │
│  │  Textual TUI │   │  Cockpit Web │   │  JeOS First-Boot   │  │
│  │  (:8090)     │   │  Extension   │   │  Module             │  │
│  └──────┬───────┘   └──────┬───────┘   └──────────┬──────────┘  │
│         │                  │                      │              │
│         └──────────┬───────┴──────────────────────┘              │
│                    ▼                                             │
│         ┌─────────────────────┐                                 │
│         │   RAG Pipeline      │                                 │
│         │  ┌───────────────┐  │                                 │
│         │  │ ChromaDB/     │  │      ┌─────────────────┐        │
│         │  │ Qdrant        │◄─┼──────│ Crawl4AI +      │        │
│         │  │ Vector Store │  │      │ Docs Ingestion  │        │
│         │  └───────────────┘  │      └─────────────────┘        │
│         └─────────┬───────────┘                                 │
│                   ▼                                              │
│  ┌────────────────────────────┐   ┌────────────────────────┐    │
│  │   unclecode-LiteLLM       │   │  LLM Server (llama.cpp) │    │
│  │   Unified LLM Interface   │──▶│  Port 8080              │    │
│  │   OpenAI-compatible API   │   │  GGUF models            │    │
│  └────────────────────────────┘   └────────────────────────┘    │
│                                           │                      │
│                              ┌────────────┴────────────┐        │
│                              │  Local GGUF Models      │        │
│                              │  LFM 2.5, Phi-4, etc.   │        │
│                              └─────────────────────────┘        │
├─────────────────────────────────────────────────────────────────┤
│  Runtime: Podman / Docker / Kubernetes (RKE2 / K3s)             │
│  Platform: openSUSE Leap 16 · Python 3.13                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Quick Start (3 commands)

```bash
# 1. Install everything (Python 3.13, Podman, dependencies)
sudo ./install.sh

# 2. Download the default LLM model (~700MB)
./scripts/download_models.sh

# 3. Build and run with Podman compose
./scripts/build_podman.sh
podman compose up -d
```

Then open `http://localhost:8090` for the TUI or talk to the API at `http://localhost:8080/v1/chat/completions`.

---

## Folder Structure

```
suse-ai-deploy/
├── install.sh                  # Master install script (Python 3.13, Podman, K8s)
├── requirements.txt            # Python 3.13+ dependencies
├── Containerfile               # Multi-stage Podman/Docker build
├── compose.yaml                # Podman compose / Docker compose
├── README.md                   # This file
├── deploy/
│   ├── docker/                 # Docker-specific files
│   │   ├── Dockerfile
│   │   ├── docker-compose.yml
│   │   ├── daemon.json
│   │   ├── suse-ai-docker.service
│   │   └── suse-ai-docker.socket
│   ├── podman/                 # Podman-specific files (RECOMMENDED)
│   │   ├── Containerfile
│   │   ├── compose.yaml
│   │   ├── suse-ai.container    # Quadlet container definition
│   │   ├── suse-ai-pod.pod      # Quadlet pod definition
│   │   ├── suse-ai.service
│   │   ├── suse-ai.socket
│   │   ├── suse-ai-ingest.service
│   │   ├── suse-ai-ingest.timer
│   │   ├── podman-commands.md
│   │   └── README.md
│   ├── kubernetes/             # K8s manifests and Helm values
│   │   ├── k8s-namespace.yaml
│   │   ├── k8s-deployment.yaml
│   │   ├── k8s-service.yaml
│   │   ├── k8s-ingress.yaml
│   │   ├── k8s-pvc.yaml
│   │   ├── k8s-configmap.yaml
│   │   ├── k8s-rbac.yaml
│   │   ├── helm-values.yaml
│   │   ├── kubectl-cheatsheet.md
│   │   └── README.md
│   ├── rancher/                # Rancher/RKE2/K3s files
│   │   ├── install-k3s.sh
│   │   ├── install-rke2.sh
│   │   ├── install-rancher.sh
│   │   ├── rke2-config.yaml
│   │   ├── cluster-registration.yaml
│   │   ├── fleet-gitrepo.yaml
│   │   ├── helm-values-rancher.yaml
│   │   ├── rancher-cli-cheatsheet.md
│   │   ├── rke2-vs-k3s-comparison.md
│   │   └── README.md
│   ├── systemd/                # systemd unit files
│   │   ├── suse-ai.socket
│   │   ├── suse-ai.service
│   │   ├── suse-ai-socket-proxy.service
│   │   ├── suse-ai-ingest.service
│   │   ├── suse-ai-ingest.timer
│   │   ├── suse-ai.env
│   │   ├── systemd-install.sh
│   │   └── README.md
│   ├── opensuse-welcome/       # openSUSE Welcome launcher integration
│   │   ├── suse-ai-welcome.desktop
│   │   ├── suse-ai-welcome-setup
│   │   ├── suse-ai-tour.json
│   │   └── INTEGRATION.md
│   ├── cockpit/                # Cockpit web UI extension
│   │   └── suse-ai/
│   │       └── manifest.json
│   └── jeos-firstboot/         # JEOS first-boot onboarding module
│       └── 04_ai_assistant.sh
├── scripts/                    # Setup, build, test & benchmark scripts
│   ├── setup_directories.sh
│   ├── download_models.sh
│   ├── build_podman.sh
│   ├── test_llm_connectivity.sh
│   ├── run_firstboot_test.sh
│   ├── benchmark_llm.py        # LLM inference latency & throughput
│   ├── benchmark_rag.py         # RAG retrieval accuracy & speed
│   └── benchmark_resources.py  # CPU/GPU/RAM utilization tracking
└── packaging/                  # OBS packaging & ISO integration
    ├── suse-ai.spec            # Full RPM spec with BuildRequires
    ├── obs-guide.md            # Step-by-step OBS project setup
    └── iso-integration-guide.md # KIWI config, Agama profiles, addon media
```

---

## Technology Choices

| Component | Choice | Why |
|-----------|--------|-----|
| **Python** | 3.13 | Default on openSUSE Leap 16, free-threading, JIT preview |
| **LLM Runtime** | llama.cpp (GGUF) | Pure C/C++, runs on CPU, quantized models (Q4_K_M) |
| **LLM Interface** | unclecode-LiteLLM | Unified OpenAI-compatible API for any backend |
| **TUI Framework** | Textual | Rich terminal UI, Python-native, async support |
| **Web UI** | Cockpit extension | Integrates with YaST/WebYaST on openSUSE |
| **RAG Store** | ChromaDB / Qdrant | Embedded or server-based vector DB |
| **Ingestion** | Crawl4AI | Async web crawler for documentation sources |
| **Embeddings** | sentence-transformers | Local embedding models, no API needed |
| **Container** | Podman 5.x (rootless) | openSUSE default, Docker-compatible, no daemon |
| **K8s** | RKE2 / K3s | SUSE ecosystem, lightweight Kubernetes distributions |
| **Package Mgr** | uv | 10-100x faster pip replacement, Rust-based |

---

## Docker vs Podman

openSUSE Leap 16 ships **Podman 5.x** as the default container engine. Both work, but Podman is recommended.

| Feature | Podman | Docker |
|---------|--------|--------|
| **Rootless by default** | Yes | Requires extra setup |
| **Daemon** | No (daemonless) | Yes (dockerd) |
| **Compose** | Built-in (`podman compose`) | Plugin (`docker compose`) |
| **CLI compatibility** | ~95% Docker-compatible | Standard |
| **openSUSE support** | First-class | Via Docker CE repo |
| **Systemd integration** | Native (`podman generate systemd`) | Via docker-compose |

### Switching to Docker

```bash
# Install Docker instead of Podman
sudo ./install.sh --docker

# Or switch manually
sudo zypper remove -y podman podman-docker
sudo zypper addrepo https://download.docker.com/linux/sles/docker-ce.repo
sudo zypper install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker
```

> **Tip:** Podman's `podman compose` is a built-in command (not `podman-compose` package). If you have issues, check with `podman compose version`.

---

## Kubernetes Deployment

### Option 1: K3s (Lightweight, Single-Node)

Best for: Edge devices, single servers, testing.

```bash
# Install K3s
sudo ./install.sh --k3s

# Deploy the AI assistant
kubectl apply -f deploy/kubernetes/k8s-namespace.yaml
kubectl apply -f deploy/kubernetes/k8s-pvc.yaml
kubectl apply -f deploy/kubernetes/k8s-configmap.yaml
kubectl apply -f deploy/kubernetes/k8s-deployment.yaml
kubectl apply -f deploy/kubernetes/k8s-service.yaml
kubectl apply -f deploy/kubernetes/k8s-ingress.yaml

# Or use Helm
helm install suse-ai ./deploy/kubernetes -f deploy/kubernetes/helm-values.yaml
```

### Option 2: RKE2 (Production, Multi-Node)

Best for: Production clusters, multi-node, HA requirements.

```bash
# Install RKE2
sudo ./install.sh --rke2

# Configure (see deploy/rancher/rke2-config.yaml)
sudo cp deploy/rancher/rke2-config.yaml /etc/rancher/rke2/config.yaml
sudo systemctl restart rke2-server

# Deploy with Helm
helm install suse-ai ./deploy/kubernetes \
    -f deploy/kubernetes/helm-values.yaml \
    -f deploy/rancher/helm-values-rancher.yaml
```

See `deploy/rancher/rke2-vs-k3s-comparison.md` for a detailed comparison.

---

## Rancher Management

For managing multiple openSUSE AI nodes:

1. **Install Rancher** (see `deploy/rancher/install-rancher.sh`)
2. **Register clusters** using `deploy/rancher/cluster-registration.yaml`
3. **Deploy via Fleet** using `deploy/rancher/fleet-gitrepo.yaml`

```bash
# Quick Rancher install on a dedicated node
./deploy/rancher/install-rancher.sh

# Register downstream clusters
kubectl apply -f deploy/rancher/cluster-registration.yaml
```

---

## openSUSE Leap 16 Notes

### Python 3.13

Leap 16 ships Python 3.13 as the default (`python313` package). Key features:

- **Free-threading** (PEP 703) — disable GIL for CPU-bound workloads
- **Improved error messages** — better debugging
- **JIT compiler** (experimental) — performance boost for hot loops

```bash
# Verify Python version
python3.13 --version

# Install development packages
sudo zypper install -y python313 python313-pip python313-devel

# Use uv for package management
uv pip install -r requirements.txt
```

### Zypper Quick Reference

| Command | Description |
|---------|-------------|
| `sudo zypper refresh` | Refresh package repositories |
| `sudo zypper update -y` | Apply all updates |
| `sudo zypper install -y <pkg>` | Install package |
| `sudo zypper search <pkg>` | Search for package |
| `rpm -q <pkg>` | Check if package is installed |
| `sudo zypper lr` | List repositories |
| `sudo zypper addrepo <URL> <alias>` | Add repository |
| `sudo zypper clean -a` | Clean cache |

---

## Ports

| Port | Service | Description |
|------|---------|-------------|
| 8080 | LLM Server | OpenAI-compatible chat API |
| 8090 | TUI / App | Textual web UI |
| 8081 | Embedding Server | Embedding model API (optional) |
| 9090 | Cockpit | Web management console |

---

## License

MIT
