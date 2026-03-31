# Docker on openSUSE Leap 16 — Deployment Guide

This folder contains Docker configuration files for deploying the SUSE AI Assistant
on **openSUSE Leap 16**.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Docker vs Podman on Leap 16](#docker-vs-podman-on-leap-16)
3. [Installation](#installation)
4. [Docker Compose V2](#docker-compose-v2)
5. [Docker Daemon Configuration](#docker-daemon-configuration)
6. [Docker Networking on Leap 16](#docker-networking-on-leap-16)
7. [Docker Storage Driver](#docker-storage-driver)
8. [Example Dockerfile](#example-dockerfile)
9. [Example docker-compose.yml](#example-docker-composeyml)
10. [Systemd Service Commands](#systemd-service-commands)
11. [Security Best Practices](#security-best-practices)
12. [Zypper Reference](#zypper-reference)
13. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
openSUSE Leap 16 Host
├── Docker Engine (docker-ce)
│   ├── containerd (container runtime)
│   ├── docker-compose-plugin (Compose V2)
│   └── /etc/docker/daemon.json
│
├── Docker Compose Project (3 services)
│   ├── llm     — LLM inference (Ollama / vLLM)
│   ├── embed   — Embedding service
│   └── app     — SUSE AI Assistant (this app)
│
└── systemd
    ├── suse-ai-docker.socket   (port 8090)
    └── suse-ai-docker.service  (docker compose up)
```

---

## Docker vs Podman on Leap 16

| Feature | Docker CE | Podman 5.4.2 (pre-installed) |
|---|---|---|
| Daemon | Yes (`dockerd`) | No (rootless by default) |
| Compose | `docker compose` (V2 plugin) | `podman compose` (built-in since 4.x) |
| CLI compatibility | Native | Via `podman-docker` symlink |
| Rootless mode | Via `rootlesskit` | Native |
| Btrfs support | Yes (`btrfs` driver) | Yes (native) |
| Systemd integration | Good | Excellent (generate systemd) |
| Docker Compose compatibility | Full | Partial (some V2 features) |
| GPU support (NVIDIA) | Via `nvidia-container-toolkit` | Via `nvidia-container-toolkit` |

### When to use Docker CE

- You need **full Docker Compose V2** compatibility.
- Your CI/CD pipeline expects exact Docker behavior.
- You require specific Docker ecosystem tools (Docker Scout, Docker Desktop, etc.).

### When to use Podman

- You want a **daemonless** container runtime.
- You prefer **rootless by default** security.
- You are running on a resource-constrained system.
- You want tight systemd integration (`podman generate systemd`).

---

## Installation

### Option A: Install Docker CE (recommended for full Compose V2 support)

> **Important:** openSUSE Leap 16 ships with `podman-docker` which provides
> `/usr/bin/docker`. This **conflicts** with the `docker` package from Docker CE.
> You must remove it first.

```bash
# Step 1: Remove podman-docker to resolve the /usr/bin/docker conflict
sudo zypper remove podman-docker

# Step 2: Add the official Docker CE repository for SUSE
sudo zypper addrepo https://download.docker.com/linux/sles/docker-ce.repo

# Step 3: Refresh package metadata
sudo zypper refresh

# Step 4: Install Docker CE and Compose V2 plugin
sudo zypper install docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Step 5: Enable and start the Docker daemon
sudo systemctl enable --now docker
```

Alternatively, Docker CE is also available from the openSUSE
**Virtualization:containers** repository:

```bash
sudo zypper addrepo https://download.opensuse.org/repositories/Virtualization:containers/openSUSE_Leap_16.0/Virtualization:containers.repo
sudo zypper refresh
sudo zypper install docker docker-compose-plugin
sudo systemctl enable --now docker
```

### Option B: Use Podman as Docker (no conflict)

If you prefer to stay with Podman and just need Docker CLI compatibility:

```bash
sudo zypper install podman podman-docker
```

This provides `/usr/bin/docker` as a symlink to `podman`. No conflict since
you are not installing Docker CE alongside it.

### Verification

```bash
docker info
docker run hello-world
```

---

## Docker Compose V2

Docker Compose V2 is a plugin integrated into the Docker CLI. On Leap 16 with
Docker CE, it is installed as part of `docker-compose-plugin`.

```bash
# Verify Compose V2 is available
docker compose version

# Usage note: it is "docker compose" (space), NOT "docker-compose" (hyphen)
docker compose up -d
docker compose logs -f app
docker compose ps
docker compose down
```

The standalone `docker-compose` (V1, Python) is **not used**. If you have it
installed, remove it:

```bash
sudo zypper remove python3-docker-compose
```

---

## Docker Daemon Configuration

Place configuration in `/etc/docker/daemon.json`. See the provided
[daemon.json](daemon.json) for a production-ready example.

Key settings for openSUSE Leap 16:

| Setting | Value | Notes |
|---|---|---|
| `storage-driver` | `btrfs` | Recommended if root filesystem is Btrfs |
| `dns` | `["8.8.8.8", "8.8.4.4"]` | Custom DNS resolvers |
| `log-opts` | `max-size`, `max-file` | Prevent unbounded log growth |
| `iptables` | `true` | Enable Docker-managed iptables rules |

After editing, restart Docker:

```bash
sudo systemctl restart docker
```

---

## Docker Networking on Leap 16

Docker creates three default networks: `bridge`, `host`, and `none`.

```bash
# List networks
docker network ls

# Create a custom bridge network
docker network create suse-ai-net

# Inspect a network
docker network inspect suse-ai-net
```

For the AI assistant stack, the provided `docker-compose.yml` creates a
dedicated `suse-ai-net` network. All three services (`llm`, `embed`, `app`)
communicate over this network.

### Firewall considerations

openSUSE Leap 16 uses `firewalld`. Ensure Docker traffic is allowed:

```bash
sudo firewall-cmd --permanent --zone=trusted --add-source=172.16.0.0/12
sudo firewall-cmd --permanent --zone=public --add-port=8090/tcp
sudo firewall-cmd --reload
```

---

## Docker Storage Driver

Leap 16 defaults to **Btrfs** as the root filesystem. Docker supports the `btrfs`
storage driver natively, which provides:

- Copy-on-write for efficient image layers.
- Subvolume snapshots for containers.
- No loopback devices needed.

Check your storage driver:

```bash
docker info | grep -i "storage driver"
```

If you see `overlay2` instead of `btrfs`, you can force Btrfs in `daemon.json`:

```json
{
  "storage-driver": "btrfs"
}
```

> **Note:** If the Docker data directory (`/var/lib/docker`) is not on a Btrfs
> filesystem, you must move it to a Btrfs subvolume or use `overlay2`.

---

## Example Dockerfile

See [Dockerfile](Dockerfile) for the full production-grade multi-stage build.

Key features:

- Base: `opensuse/leap:16`
- Python 3.13 (`python313` package)
- Multi-stage: builder → python-deps → runtime
- Non-root user (`appuser`)
- `uv` for fast dependency installation
- `HEALTHCHECK` instruction
- OCI-compliant labels

Build the image:

```bash
docker compose build
# or
docker build -t suse-ai-assistant:latest .
```

---

## Example docker-compose.yml

See [docker-compose.yml](docker-compose.yml) for the full 3-service stack.

Services:

| Service | Image / Build | Port | Description |
|---|---|---|---|
| `llm` | `ollama/ollama:latest` | 11434 | LLM inference server |
| `embed` | Custom build | 11435 | Embedding generation service |
| `app` | Custom build | 8090 | SUSE AI Assistant web app |

Run the stack:

```bash
docker compose up -d
docker compose logs -f
docker compose ps
docker compose down
```

---

## Systemd Service Commands

The provided systemd units allow the AI assistant to start automatically with
the system.

```bash
# Install the systemd units
sudo cp suse-ai-docker.socket /etc/systemd/system/
sudo cp suse-ai-docker.service /etc/systemd/system/
sudo systemctl daemon-reload

# Enable and start (socket activation on port 8090)
sudo systemctl enable --now suse-ai-docker.socket

# Check status
sudo systemctl status suse-ai-docker.socket
sudo systemctl status suse-ai-docker.service

# View logs
sudo journalctl -u suse-ai-docker.service -f

# Stop
sudo systemctl stop suse-ai-docker.service
sudo systemctl stop suse-ai-docker.socket

# Restart after config change
sudo systemctl restart suse-ai-docker.service
```

### Docker daemon service

```bash
# Docker Engine itself runs as a systemd service
sudo systemctl status docker
sudo systemctl restart docker
sudo journalctl -u docker -f
```

---

## Security Best Practices

### 1. Run containers as non-root

The provided Dockerfile creates a dedicated `appuser` with UID/GID `1000`.

### 2. Use read-only root filesystem

In `docker-compose.yml`:

```yaml
read_only: true
tmpfs:
  - /tmp
  - /app/.cache
```

### 3. Limit container capabilities

```yaml
cap_drop:
  - ALL
cap_add:
  - NET_BIND_SERVICE
```

### 4. Enable user namespace remapping

In `/etc/docker/daemon.json`:

```json
{
  "userns-remap": "default"
}
```

### 5. Scan images for vulnerabilities

```bash
docker scout cves suse-ai-assistant:latest
```

### 6. Use Docker secrets for sensitive data

```yaml
secrets:
  api_key:
    file: ./secrets/api_key.txt
```

### 7. Keep Docker Engine updated

```bash
sudo zypper refresh
sudo zypper update docker-ce docker-ce-cli containerd.io
```

### 8. Restrict Docker socket access

```bash
sudo usermod -aG docker youruser
# Never expose /var/run/docker.sock to containers
```

### 9. Enable live-restore

Prevents container downtime during Docker daemon restarts:

```json
{
  "live-restore": true
}
```

### 10. Set resource limits

```yaml
deploy:
  resources:
    limits:
      cpus: '2.0'
      memory: 4G
    reservations:
      cpus: '0.5'
      memory: 1G
```

---

## Zypper Reference

### Docker CE Installation (Option A)

```bash
# Option A: Install Docker CE (remove podman-docker first)
sudo zypper remove podman-docker
sudo zypper addrepo https://download.docker.com/linux/sles/docker-ce.repo
sudo zypper refresh
sudo zypper install docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker
```

### Podman as Docker (Option B)

```bash
# Option B: Use Podman as Docker (no conflict)
sudo zypper install podman podman-docker
```

### Docker Compose V2

```bash
# Docker Compose V2 (included with docker-ce)
docker compose version
```

### Verification

```bash
# Verify
docker info
docker run hello-world
```

### Useful zypper commands for container management

```bash
# List installed container-related packages
zypper search -i container podman docker

# Check for updates
sudo zypper refresh && sudo zypper list-updates

# Remove Docker CE completely
sudo zypper remove docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo zypper removerepo docker-ce

# Install NVIDIA container toolkit (for GPU support)
sudo zypper addrepo https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo
sudo zypper refresh
sudo zypper install nvidia-container-toolkit
```

---

## Troubleshooting

### `docker: Cannot connect to the Docker daemon`

```bash
sudo systemctl start docker
sudo usermod -aG docker $USER
# Log out and back in, or: newgrp docker
```

### `conflict with podman-docker`

```bash
sudo zypper remove podman-docker
sudo zypper install docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

### Btrfs storage driver not used

Ensure `/var/lib/docker` is on a Btrfs filesystem:

```bash
findmnt /var/lib/docker
# If not Btrfs, move the data directory:
sudo systemctl stop docker
sudo mv /var/lib/docker /var/lib/docker.bak
sudo btrfs subvolume create /var/lib/docker
sudo systemctl start docker
```

### Container logs filling disk

Set log rotation in `daemon.json` (see [daemon.json](daemon.json)):

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

### Firewalld blocking container traffic

```bash
sudo firewall-cmd --permanent --zone=trusted --add-interface=docker0
sudo firewall-cmd --reload
```

---

## File Reference

| File | Description |
|---|---|
| `README.md` | This documentation |
| `Dockerfile` | Multi-stage production image for the AI assistant |
| `docker-compose.yml` | 3-service Compose stack (llm, embed, app) |
| `daemon.json` | Example Docker daemon configuration |
| `suse-ai-docker.socket` | systemd socket unit (port 8090) |
| `suse-ai-docker.service` | systemd service unit (docker compose) |
