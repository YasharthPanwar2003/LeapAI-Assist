# SUSE AI Assistant — systemd Deployment Guide

Complete reference for deploying SUSE AI Assistant with systemd units on openSUSE Leap 16.
Covers Podman (rootless), Docker (root), socket activation, timers, and Quadlet.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Systemd Units Reference](#systemd-units-reference)
3. [Quick Start — User Session (Podman)](#quick-start--user-session-podman)
4. [Quick Start — System Install (Docker)](#quick-start--system-install-docker)
5. [Socket Activation Explained](#socket-activation-explained)
6. [Nightly Ingestion Timer](#nightly-ingestion-timer)
7. [Environment Configuration](#environment-configuration)
8. [Bug Fixes Applied](#bug-fixes-applied)
9. [systemctl Cheatsheet](#systemctl-cheatsheet)
10. [Troubleshooting](#troubleshooting)
11. [File Map — All systemd Files](#file-map--all-systemd-files)

---

## Architecture Overview

```
                    ┌─────────────────────────────────┐
                    │       systemd (PID 1)           │
                    │                                  │
  Port 8090 ──────►│  suse-ai.socket (listens)        │
                    │       │                          │
                    │       │ first connection          │
                    │       ▼                          │
                    │  suse-ai.service                 │
                    │       │                          │
                    │       ▼                          │
                    │  ┌─────────┐  ┌────────┐  ┌────┐│
                    │  │llm:8080│  │embed:  │  │app ││
                    │  │        │  │8081    │  │8090││
                    │  └─────────┘  └────────┘  └────┘│
                    │       pod (shared network ns)     │
                    └─────────────────────────────────┘

  Nightly 03:00 ──►  suse-ai-ingest.timer
                         │
                         ▼
                    suse-ai-ingest.service (oneshot)
                         │
                         ▼
                    Document re-indexing
```

### Two Deployment Modes

| Mode | Scope | Container Runtime | Install Location | Use Case |
|------|-------|------------------|-----------------|----------|
| **User Session** | `--user` | Podman (rootless) | `~/.config/systemd/user/` | Development, single-user |
| **System** | root | Docker (daemon) | `/etc/systemd/system/` | Production, multi-user servers |

---

## Systemd Units Reference

### Files in this folder

| File | Type | Purpose |
|------|------|---------|
| `suse-ai.socket` | Socket | Listens on port 8090, activates service on first connection |
| `suse-ai.service` | Service | Main application container |
| `suse-ai-socket-proxy.service` | Service | Alternative socket-activated startup variant |
| `suse-ai-ingest.service` | Service (oneshot) | Document ingestion/re-indexing pipeline |
| `suse-ai-ingest.timer` | Timer | Triggers ingest.service at 03:00 daily |
| `suse-ai.env` | Environment | Default configuration (loaded by service) |
| `systemd-install.sh` | Script | Automated install/uninstall helper |

### Also see (runtime-specific)

| Location | Files | Description |
|----------|-------|-------------|
| `deploy/podman/` | `suse-ai.service`, `suse-ai.socket`, `suse-ai-ingest.*` | Podman-optimized versions |
| `deploy/podman/` | `suse-ai.container`, `suse-ai-pod.pod` | Quadlet definitions (Podman 5.x) |
| `deploy/docker/` | `suse-ai-docker.service`, `suse-ai-docker.socket` | Docker Compose versions |

---

## Quick Start — User Session (Podman)

```bash
# 1. Copy units to user systemd directory
mkdir -p ~/.config/systemd/user
cp deploy/systemd/suse-ai.socket ~/.config/systemd/user/
cp deploy/systemd/suse-ai.service ~/.config/systemd/user/
cp deploy/systemd/suse-ai-ingest.service ~/.config/systemd/user/
cp deploy/systemd/suse-ai-ingest.timer ~/.config/systemd/user/

# 2. Copy environment file
mkdir -p ~/.config/suse-ai
cp deploy/systemd/suse-ai.env ~/.config/suse-ai/env

# 3. Reload systemd
systemctl --user daemon-reload

# 4. Enable socket activation (lazy start on first connection)
systemctl --user enable --now suse-ai.socket

# 5. Enable nightly ingestion timer
systemctl --user enable --now suse-ai-ingest.timer

# 6. Test (first connection starts the service)
curl -s http://localhost:8090/health
```

### Or use the automated installer:

```bash
./deploy/systemd/systemd-install.sh --user
```

---

## Quick Start — System Install (Docker)

```bash
# 1. Ensure Docker is installed (not podman-docker!)
sudo zypper remove -y podman-docker
sudo zypper install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker

# 2. Copy Docker-specific units
sudo cp deploy/docker/suse-ai-docker.service /etc/systemd/system/
sudo cp deploy/docker/suse-ai-docker.socket /etc/systemd/system/

# 3. Copy generic units (socket activation, timer)
sudo cp deploy/systemd/suse-ai.socket /etc/systemd/system/
sudo cp deploy/systemd/suse-ai-ingest.service /etc/systemd/system/
sudo cp deploy/systemd/suse-ai-ingest.timer /etc/systemd/system/

# 4. Copy environment file
sudo mkdir -p /etc/suse-ai
sudo cp deploy/systemd/suse-ai.env /etc/suse-ai/env

# 5. Reload and enable
sudo systemctl daemon-reload
sudo systemctl enable --now suse-ai-docker.socket
sudo systemctl enable --now suse-ai-ingest.timer

# 6. Test
curl -s http://localhost:8090/health
```

### Or use the automated installer:

```bash
sudo ./deploy/systemd/systemd-install.sh --system
```

---

## Socket Activation Explained

Socket activation is a systemd feature that defers service startup until the first client connects.

### How it works

```
  [Idle state - saves ~200MB RAM]
  systemd listens on :8090 ── nothing running

  [Client connects to :8090]
  systemd ──► starts suse-ai.service
  systemd ──► passes socket fd to service
  service ──► container starts, binds to socket
  service ──► handles client request

  [All subsequent connections go directly to running service]
```

### Enable vs Always-On

```bash
# Socket activation (lazy start — recommended for dev/laptops)
systemctl --user enable --now suse-ai.socket
# Do NOT enable suse-ai.service — the socket starts it

# Always-on (production servers)
systemctl --user enable --now suse-ai.service
# Do NOT enable suse-ai.socket — it will conflict on port 8090
```

### Socket unit configuration

```ini
[Socket]
ListenStream=8090       # TCP port to listen on
Accept=no               # Pass socket fd to service (NOT per-connection)
NoDelay=true            # Disable Nagle's algorithm
KeepAlive=true          # TCP keepalive enabled
KeepAliveTimeSec=30     # First keepalive after 30s idle
Backlog=128             # Pending connection queue size
```

---

## Nightly Ingestion Timer

The ingestion pipeline re-indexes documents from `/var/lib/suse-ai/documents/` into the vector database.

### Timer configuration

```ini
[Timer]
OnCalendar=*-*-* 03:00:00    # Every day at 3:00 AM
Persistent=true                # Catch up if system was off
RandomizedDelaySec=300         # Random 0-5 min delay
AccuracySec=1m                 # Start within 1 minute of scheduled time
```

### Ingest modes

| Mode | Description | Command |
|------|-------------|---------|
| `full` | Delete all vectors, re-index everything | `python -m suse_ai.ingest --mode full` |
| `incremental` | Only index new/changed documents | `python -m suse_ai.ingest --mode incremental` |

### Override the mode via environment:

```bash
# In ~/.config/suse-ai/env or /etc/suse-ai/env
INGEST_MODE=incremental
```

### Manual trigger

```bash
# Run ingestion right now
systemctl --user start suse-ai-ingest

# Watch the logs
journalctl --user -u suse-ai-ingest -f

# Check last run
systemctl --user status suse-ai-ingest
journalctl --user -u suse-ai-ingest --since "today" --until "now"
```

### List all timers

```bash
systemctl --user list-timers --all
```

---

## Environment Configuration

The service loads environment variables from:

| Scope | Path | Priority |
|-------|------|----------|
| User session | `~/.config/suse-ai/env` | User overrides |
| System | `/etc/suse-ai/env` | Global defaults |

### Key variables

```bash
# LLM
LLM_BASE_URL=http://llm:11434        # Ollama/LiteLLM endpoint
LLM_MODEL=llama3                      # Model name
LLM_MAX_TOKENS=4096                   # Max response tokens
LLM_TEMPERATURE=0.7                   # Creativity (0-1)

# Embeddings
EMBED_BASE_URL=http://embed:11435     # Embedding server
EMBED_MODEL=nomic-embed-text          # Embedding model
EMBED_DIMENSIONS=768                  # Vector dimensions

# RAG
RAG_BACKEND=qdrant                    # qdrant or chromadb
RAG_TOP_K=5                           # Number of results
RAG_SCORE_THRESHOLD=0.7               # Minimum similarity score

# Application
LOG_LEVEL=info                        # debug, info, warn, error
APP_PORT=8090                         # Listen port
APP_WORKERS=2                         # Worker processes

# Container
CONTAINER_MEMORY=3g                   # Memory limit
CONTAINER_CPUS=2                      # CPU limit

# Hardware
GPU_DEVICE=auto                       # auto, cpu, cuda:0
CUDA_VISIBLE_DEVICES=0                # GPU device index
```

### Override with systemd drop-in

```bash
# Create a drop-in override
systemctl --user edit suse-ai.service

# This creates ~/.config/systemd/user/suse-ai.service.d/override.conf
# Example:
[Service]
Environment="LLM_MODEL=mistral"
Environment="LOG_LEVEL=debug"
MemoryMax=8G
```

---

## Bug Fixes Applied

These fixes were applied to the original systemd files you provided:

### 1. Type=notify → Type=simple

**Problem:** The original `suse-ai.service` used `Type=notify`, which tells systemd to wait for the service to send a `READY=1` notification via sd_notify(). Podman does NOT support sd_notify(), so the service would hang indefinitely waiting for the notification, eventually timing out.

**Fix:** Changed to `Type=simple` — systemd considers the service started immediately after the fork (when ExecStart begins). This is the correct type for container runtimes that don't integrate with sd_notify.

```ini
# BEFORE (broken):
[Service]
Type=notify

# AFTER (fixed):
[Service]
Type=simple
```

### 2. User=%i removed from user session units

**Problem:** The original unit had `User=%i`, which tries to set the user to the instance name. In `--user` session mode, the service already runs as the invoking user. Setting `User=` explicitly in a user session unit causes permission issues and is redundant.

**Fix:** Removed `User=` entirely from all user session units.

```ini
# BEFORE (broken for --user):
[Service]
User=%i

# AFTER (fixed):
[Service]
# No User= — user session units run as invoking user
```

### 3. Wants=podman.service removed

**Problem:** The original unit had `Wants=podman.service` and/or `BindsTo=podman.service`. Podman is DAEMONLESS — there is no `podman.service` running in the background. This reference causes systemd to wait for a non-existent service or log warnings.

**Fix:** Removed all references to `podman.service`. Podman is invoked directly by the `ExecStart=` command.

```ini
# BEFORE (broken):
[Unit]
Wants=podman.service
BindsTo=podman.service

# AFTER (fixed):
[Unit]
# No podman.service reference — Podman is daemonless
After=network-online.target
Wants=network-online.target
```

### 4. Docker service requires docker.service

**Problem:** Unlike Podman, Docker IS a daemon. Docker-based services MUST have `Requires=docker.service` and `After=docker.service`, otherwise the service starts before Docker is ready.

**Fix:** The Docker-specific service (`suse-ai-docker.service`) correctly includes these dependencies.

```ini
[Unit]
After=docker.service network-online.target
Requires=docker.service network-online.target
```

### 5. ExecStop/ExecStopPost for clean container cleanup

**Problem:** Original service did not properly clean up containers on stop.

**Fix:** Added `ExecStop` for graceful shutdown and `ExecStopPost` for forced removal.

```ini
ExecStop=/usr/bin/podman stop --time=30 suse-ai
ExecStopPost=/usr/bin/podman rm -f suse-ai 2>/dev/null || true
```

---

## systemctl Cheatsheet

### Service Management

```bash
# Start / Stop / Restart
systemctl --user start suse-ai
systemctl --user stop suse-ai
systemctl --user restart suse-ai

# Enable / Disable (start on boot/login)
systemctl --user enable suse-ai
systemctl --user disable suse-ai

# Enable and start now
systemctl --user enable --now suse-ai

# Status
systemctl --user status suse-ai
systemctl --user is-active suse-ai
systemctl --user is-enabled suse-ai
systemctl --user is-failed suse-ai
```

### Socket Management

```bash
# Enable socket activation
systemctl --user enable --now suse-ai.socket

# Check socket status
systemctl --user status suse-ai.socket

# Verify port is listening
ss -tlnp | grep 8090

# Disable socket (switch to always-on mode)
systemctl --user disable --now suse-ai.socket
```

### Timer Management

```bash
# List all timers
systemctl --user list-timers --all

# Enable / disable timer
systemctl --user enable --now suse-ai-ingest.timer
systemctl --user disable suse-ai-ingest.timer

# Manually trigger the timed service
systemctl --user start suse-ai-ingest

# Check timer status
systemctl --user status suse-ai-ingest.timer
systemctl --user show suse-ai-ingest.timer --property=NextElapseUSecMonotonic
```

### Logs

```bash
# Follow logs (like tail -f)
journalctl --user -u suse-ai -f

# Logs since boot
journalctl --user -u suse-ai -b

# Logs from today
journalctl --user -u suse-ai --since "today"

# Logs from last 100 lines
journalctl --user -u suse-ai -n 100

# Logs with timestamps
journalctl --user -u suse-ai -o short-precise

# Ingest logs
journalctl --user -u suse-ai-ingest -f
```

### Debugging

```bash
# Verify unit file syntax
systemd-analyze verify suse-ai.service

# Show full unit configuration (all defaults + overrides)
systemctl --user show suse-ai.service

# Show runtime dependencies
systemctl --user list-dependencies suse-ai.service

# Analyze boot time
systemd-analyze blame | grep suse-ai

# Check unit file on disk
systemd-analyze cat-config suse-ai.service

# Reset failed state
systemctl --user reset-failed suse-ai
```

### Drop-in Overrides

```bash
# Edit drop-in override (creates override.conf)
systemctl --user edit suse-ai.service

# View drop-in directory
ls ~/.config/systemd/user/suse-ai.service.d/

# Remove all drop-ins
rm -rf ~/.config/systemd/user/suse-ai.service.d/
systemctl --user daemon-reload
```

---

## Troubleshooting

### Service won't start

```bash
# Check the logs for errors
journalctl --user -u suse-ai -n 50 --no-pager

# Verify container image exists
podman images | grep suse-ai

# Verify the container can run manually
podman run --rm localhost/suse-ai:latest python -c "print('OK')"

# Verify systemd unit syntax
systemd-analyze verify ~/.config/systemd/user/suse-ai.service
```

### Port 8090 already in use

```bash
# Check what's using the port
ss -tlnp | grep 8090

# If the socket is bound but service failed:
systemctl --user stop suse-ai.socket
systemctl --user stop suse-ai
systemctl --user reset-failed suse-ai
systemctl --user start suse-ai.socket
```

### Timer not firing

```bash
# Check timer is enabled and active
systemctl --user status suse-ai-ingest.timer

# Check next scheduled run
systemctl --user list-timers --all | grep ingest

# Check if the service itself has errors
journalctl --user -u suse-ai-ingest --since "yesterday"

# Manually trigger to test
systemctl --user start suse-ai-ingest
journalctl --user -u suse-ai-ingest -f
```

### Podman permission denied

```bash
# Check subuid/subgid mappings (required for rootless Podman)
cat /etc/subuid | grep $(whoami)
cat /etc/subgid | grep $(whoami)

# If missing, add them:
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $(whoami)

# Verify XDG_RUNTIME_DIR is set
echo $XDG_RUNTIME_DIR
# Should be: /run/user/$(id -u)

# If unset, add to ~/.bashrc:
echo 'export XDG_RUNTIME_DIR=/run/user/$(id -u)' >> ~/.bashrc
```

### Docker: container fails to start

```bash
# Ensure Docker daemon is running
sudo systemctl status docker

# Check Docker logs
sudo journalctl -u docker -n 50

# Test Docker directly
sudo docker compose -f /opt/suse-ai-deploy/deploy/docker/docker-compose.yml config
sudo docker compose -f /opt/suse-ai-deploy/deploy/docker/docker-compose.yml up --abort-on-container-exit
```

---

## File Map — All systemd Files

```
deploy/
├── systemd/                          # ⭐ THIS FOLDER — standalone units
│   ├── suse-ai.socket               #   Socket activation (port 8090)
│   ├── suse-ai.service              #   Main service (runtime-agnostic)
│   ├── suse-ai-socket-proxy.service #   Alternative socket-activated variant
│   ├── suse-ai-ingest.service       #   Document ingestion (oneshot)
│   ├── suse-ai-ingest.timer         #   Nightly timer (03:00)
│   ├── suse-ai.env                  #   Default environment config
│   ├── systemd-install.sh           #   Install/uninstall helper script
│   └── README.md                    #   This file
│
├── podman/                           # Podman-specific units & Quadlet
│   ├── suse-ai.service              #   Podman-optimized service
│   ├── suse-ai.socket               #   Podman socket unit
│   ├── suse-ai-ingest.service       #   Podman ingest service
│   ├── suse-ai-ingest.timer         #   Podman ingest timer
│   ├── suse-ai.container            #   Quadlet .container definition
│   ├── suse-ai-pod.pod              #   Quadlet .pod definition
│   ├── Containerfile                #   Podman Containerfile
│   ├── compose.yaml                 #   podman compose file
│   └── ...
│
├── docker/                           # Docker-specific units
│   ├── suse-ai-docker.service       #   Docker Compose service
│   ├── suse-ai-docker.socket        #   Docker socket unit
│   ├── Dockerfile                   #   Docker Dockerfile
│   ├── docker-compose.yml           #   Docker Compose file
│   └── ...
│
└── kubernetes/                       # K8s (no systemd — uses K8s controllers)
    ├── k8s-deployment.yaml          #   Deployment (like systemd service)
    ├── k8s-service.yaml             #   Service (like systemd socket)
    └── ...
```

---

*Last updated: March 2026 — openSUSE Leap 16, Podman 5.4.2, Docker CE 27.x*
