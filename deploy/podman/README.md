# Podman on openSUSE Leap 16

> **Comprehensive deployment guide for running containers with Podman 5.x on openSUSE Leap 16**

---

## Table of Contents

1. [Overview](#overview)
2. [Installation](#installation)
3. [Podman vs Docker Architecture](#podman-vs-docker-architecture)
4. [Rootless Containers](#rootless-containers)
5. [Podman Compose](#podman-compose)
6. [Quadlet (Recommended Approach)](#quadlet-recommended-approach)
7. [systemd Integration](#systemd-integration)
8. [Networking](#networking)
9. [Volumes](#volumes)
10. [Image Management](#image-management)
11. [Security](#security)
12. [Podman Pods](#podman-pods)
13. [Troubleshooting](#troubleshooting)
14. [Command Reference](#command-reference)

---

## Overview

**Podman 5.4.2** is the default container engine on openSUSE Leap 16. It provides a
Docker-compatible CLI without requiring a background daemon, making it inherently
more secure and suitable for both development and production workloads.

Key characteristics of Podman on Leap 16:

| Feature | Details |
|---|---|
| **Version** | 5.4.2 (pre-installed) |
| **Architecture** | Daemonless (no `podman.service`) |
| **Security** | Rootless by default, SELinux-aware |
| **Compose** | Built-in `podman compose` (Podman 4.x+) |
| **systemd** | Quadlet (`.container` files) recommended |
| **Docker compat** | `podman-docker` package (conflicts with `docker`) |

---

## Installation

Podman is pre-installed on Leap 16. To install or update:

```bash
# Core container engine (pre-installed, ensure latest)
sudo zypper install podman

# Docker CLI compatibility (provides /usr/bin/docker symlink)
# WARNING: CONFLICTS with the 'docker' package — cannot coexist
sudo zypper install podman-docker

# OCI ecosystem tools
sudo zypper install buildah skopeo

# Compose compatibility (legacy — podman compose is built-in)
# Only needed for scripts that call 'podman-compose' binary
sudo zypper install python313-podman-compose

# Useful utilities
sudo zypper install podman-curl    # Healthcheck support (curl in containers)
sudo zypper install slirp4netns    # Rootless networking helper
sudo zypper install fuse-overlayfs # Rootless overlay storage driver
```

### Verify installation

```bash
podman --version
# podman version 5.4.2

podman info --format '{{.Host.RemoteSocket.Path}}'
# (empty — daemonless, no socket)

podman info --format '{{.Host.Security.Rootless}}'
# true
```

### package conflict warning

The `podman-docker` package **conflicts** with the `docker` package. You cannot
have both installed simultaneously. If migrating from Docker:

```bash
# Remove Docker first
sudo zypper remove docker docker-compose

# Then install Podman Docker compatibility
sudo zypper install podman-docker

# Verify the docker CLI is now Podman
docker info | head -1
# Should show: Podman Engine
```

---

## Podman vs Docker Architecture

### Docker Architecture (Daemon-based)

```
┌─────────────┐     ┌─────────────┐     ┌──────────────┐
│  docker CLI │────▶│ dockerd     │────▶│ containerd   │
│             │     │ (daemon)    │     │ (runc)       │
└─────────────┘     └─────────────┘     └──────────────┘
                          │
                    ┌─────┴─────┐
                    │ /var/run/ │
                    │ docker.sock│
                    └───────────┘
                    Requires: sudo / docker group
                    Attack surface: daemon socket, daemon process
```

### Podman Architecture (Daemonless)

```
┌─────────────┐     ┌──────────────┐
│ podman CLI  │────▶│ conmon + runc│
│ (fork/exec) │     │ (per container)│
└─────────────┘     └──────────────┘
                          │
                    No daemon process
                    No root socket
                    No persistent attack surface
                    Each container = isolated child process
```

### Key Differences

| Aspect | Docker | Podman |
|---|---|---|
| **Daemon** | Required (dockerd) | None (daemonless) |
| **Root requirement** | Usually needs root or docker group | True rootless by default |
| **Systemd integration** | Via daemon socket | Native (Quadlet, generate systemd) |
| `podman/docker service` | Required for socket activation | Does NOT exist (daemonless) |
| **Compose** | `docker compose` (plugin) | `podman compose` (built-in) |
| **Kubernetes YAML** | Limited | Full `podman generate kube` / `podman play kube` |
| **Pods** | No native support | Native Kubernetes-compatible pods |
| **CLI compatibility** | N/A | Drop-in replacement (`podman-docker`) |
| **Fork model** | Client-server (REST API) | Fork-exec (direct) |

---

## Rootless Containers

Podman runs containers as unprivileged users by default on Leap 16.

### Subordinate UID/GID ranges

Leap 16 automatically configures subordinate ranges for new users. Verify:

```bash
# Check user's subordinate ranges
grep $(whoami) /etc/subuid /etc/subgid

# Typically returns:
# username:100000:65536
# username:100000:65536
```

### Rootless configuration

```bash
# Set up rootless Podman (usually automatic on Leap 16)
podman system migrate

# Configure storage for rootless
# Edit ~/.config/containers/storage.conf
cat > ~/.config/containers/storage.conf << 'EOF'
[storage]
driver = "overlay"
runroot = "/run/user/$UID/containers"
graphroot = "$HOME/.local/share/containers/storage"

[storage.options]
override_kernel_check = "true"
size = ""
EOF
```

### Running as a specific user

```bash
# Run container as current user (rootless)
podman run --rm alpine whoami
# 1000 (your UID, not root)

# Map current user into container (recommended for file access)
podman run --rm --userns=keep-id alpine whoami
# yourusername
```

### Rootless limitations

| Limitation | Workaround |
|---|---|
| Cannot bind to ports < 1024 | Use higher ports or `sysctl net.ipv4.ip_unprivileged_port_start=80` |
| Cannot mount certain filesystems | Use `--mount type=bind` instead of `--mount type=tmpfs` |
| Overlay may not work on some filesystems | Use `fuse-overlayfs` or `vfs` driver |
| Cgroup v2 required for resource limits | Leap 16 uses cgroup v2 by default |

---

## Podman Compose

`podman compose` has been built-in since Podman 4.x. **Do NOT use** `docker-compose`
or `podman-compose` (legacy Python script) on Leap 16.

### Basic usage

```bash
# Start services defined in compose.yaml
podman compose up -d

# View logs
podman compose logs -f

# Stop services
podman compose down

# Rebuild and restart
podman compose up -d --build

# Scale a service
podman compose up -d --scale app=3
```

### compose.yaml compatibility notes

Podman compose supports most Docker Compose v2/v3 fields with some differences:

| Feature | Docker Compose | Podman Compose |
|---|---|---|
| `container_name` | Supported | Supported but **not recommended** |
| `depends_on` with conditions | Full support | Full support |
| `healthcheck` | Full support | Full support |
| `volumes:` (named) | Full support | Full support |
| `networks:` | Full support | Full support |
| `deploy.resources` | Swarm only | Supported (Podman-specific) |
| `security_opt` | Full support | Full support (+ SELinux `:z`/`:Z`) |
| ` userns_mode` | Limited | Full support |

### Tips for Podman Compose on Leap 16

```yaml
# compose.yaml — Podman-compatible best practices
services:
  app:
    image: localhost/myapp:latest
    # Avoid container_name — let Podman generate predictable names
    # container_name: myapp  ← DO NOT USE
    ports:
      - "8080:8080"
    volumes:
      # Use :z (single label) or :Z (private label) for SELinux
      - ./data:/app/data:z
    environment:
      - PODMAN_USERNS=keep-id
    # Use userns for rootless file ownership
    userns_mode: keep-id
```

---

## Quadlet (Recommended Approach)

[Quadlet](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html) is the
Podman 5.x recommended way to define containers for systemd. It uses `.container`,
`.pod`, `.network`, `.volume`, and `.image` unit files that are automatically
converted to proper systemd service units.

### How Quadlet works

```
~/.config/containers/systemd/          # User session (recommended)
├── myapp.container                    # → systemd --user service
├── myapp-pod.pod                      # → systemd --user service (pod)
├── mynet.network                      # → systemd --user service (network)
└── mydata.volume                      # → systemd --user service (volume)

/etc/containers/systemd/              # System-wide (root)
├── myapp.container
└── myapp-pod.pod
```

When you run `systemctl --user daemon-reload`, Quadlet generates the corresponding
systemd units in `/run/user/$UID/systemd/generator/`.

### Container file example

```ini
# ~/.config/containers/systemd/suse-ai.container
[Container]
# Image to run (local or registry)
Image=localhost/suse-ai:latest

# Pod to join (creates shared network namespace)
Pod=suse-ai-pod

# Port mapping
PublishPort=8090:8090

# Volume mounts
Volume=/var/lib/suse-ai:/data:rw,z

# Environment variables
Environment=PODMAN_USERNS=keep-id
Environment=RUST_LOG=info

# Auto-update from registry
AutoUpdate=registry

# Health checks
HealthCmd=curl -sf http://localhost:8080/v1/models || exit 1
HealthInterval=30s
HealthTimeout=10s
HealthStartPeriod=60s
HealthRetries=3

# Resource limits
Memory=3G

[Service]
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
```

### Pod file example

```ini
# ~/.config/containers/systemd/suse-ai-pod.pod
[Pod]
PublishPort=8090:8090

[Install]
WantedBy=default.target
```

### Network file example

```ini
# ~/.config/containers/systemd/frontend.network
[Network]
Subnet=10.89.0.0/24
Internal=false
```

### Volume file example

```ini
# ~/.config/containers/systemd/data.volume
[Volume]
Driver=local
```

### Deploying Quadlet units

```bash
# 1. Copy Quadlet files to the right location
mkdir -p ~/.config/containers/systemd/
cp *.container *.pod ~/.config/containers/systemd/

# 2. Reload systemd to generate units from Quadlet files
systemctl --user daemon-reload

# 3. Enable and start
systemctl --user enable --now suse-ai-pod
systemctl --user enable --now suse-ai

# 4. Check status
systemctl --user status suse-ai
podman ps

# 5. View logs
journalctl --user -u suse-ai -f
```

### Quadlet key directives reference

| Directive | Section | Description |
|---|---|---|
| `Image=` | `[Container]` | Container image to run |
| `Pod=` | `[Container]` | Name of pod to join |
| `PublishPort=` | `[Container]` | Port mapping (host:container) |
| `Volume=` | `[Container]` | Volume mount (host:container:options) |
| `Environment=` | `[Container]` | Environment variable |
| `AutoUpdate=` | `[Container]` | Auto-update policy (`registry`, `local`, `none`) |
| `Exec=` | `[Container]` | Override container entrypoint command |
| `Label=` | `[Container]` | Container labels |
| `Secret=` | `[Container]` | Secret to mount from Podman secret store |
| `HealthCmd=` | `[Container]` | Healthcheck command |
| `HealthInterval=` | `[Container]` | Time between healthchecks |
| `HealthTimeout=` | `[Container]` | Healthcheck timeout |
| `HealthRetries=` | `[Container]` | Consecutive failures before unhealthy |
| `Memory=` | `[Container]` | Memory limit |
| `CpuShares=` | `[Container]` | CPU share weight |
| `SecurityLabelDisable=` | `[Container]` | Disable SELinux labeling |
| `DropCapability=` | `[Container]` | Drop specific Linux capability |
| `ReadOnly=` | `[Container]` | Read-only root filesystem |
| `Subnet=` | `[Network]` | Network subnet CIDR |
| `Driver=` | `[Volume]` | Volume driver |

---

## systemd Integration

### Critical: Podman is daemonless

Podman has **NO daemon process** and **NO `podman.service`**. Never include:

```ini
# WRONG — these will cause errors
Wants=podman.service        # ← Does NOT exist
After=podman.service        # ← Does NOT exist
BindsTo=podman.service      # ← Does NOT exist
```

### Critical: Type=simple, NOT notify

Podman does **not** support `sd_notify()` (systemd notification). Always use:

```ini
# WRONG — Type=notify will timeout
[Service]
Type=notify                  # ← NEVER use with Podman

# CORRECT
[Service]
Type=simple                  # ← Always use with Podman
```

### User session units

For rootless containers, use `systemctl --user`:

```ini
# ~/.config/systemd/user/suse-ai.service
[Unit]
Description=SUSE AI Application Container
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
# Do NOT set User= — user session units run as the invoking user
ExecStart=/usr/bin/podman run \
    --rm \
    --name suse-ai \
    --userns=keep-id \
    -p 8090:8090 \
    -v /var/lib/suse-ai:/data:z \
    -e PODMAN_USERNS=keep-id \
    localhost/suse-ai:latest
ExecStop=/usr/bin/podman stop suse-ai
ExecStopPost=/usr/bin/podman rm suse-ai
Environment=PODMAN_USERNS=keep-id
Restart=on-failure
RestartSec=10
TimeoutStartSec=300
TimeoutStopSec=30

[Install]
WantedBy=default.target
```

### Socket activation

```ini
# ~/.config/systemd/user/suse-ai.socket
[Unit]
Description=SUSE AI Socket (port 8090)

[Socket]
ListenStream=8090

[Install]
WantedBy=default.target
```

### Enabling user services to run without login

```bash
# Enable lingering so user services run even when not logged in
loginctl enable-linger $(whoami)

# Verify lingering is enabled
loginctl show-user $(whoami) -p Linger
# Linger=yes
```

### Generating systemd units from containers

```bash
# Auto-generate a systemd unit from an existing container
podman generate systemd --name myapp --files --new

# This creates a .service file with the correct Type=simple
# Copy to ~/.config/systemd/user/ and enable
```

---

## Networking

### Default networking

Podman uses `podman` (CNI) or `netavark` as the network backend. On Leap 16,
netavark is the default for Podman 5.x.

```bash
# List networks
podman network ls

# Inspect default network
podman network inspect podman
```

### Create a custom bridge network

```bash
# Create network
podman network create mynet --subnet 10.89.0.0/24

# Use in a container
podman run --rm --network mynet alpine

# Use in compose.yaml
# networks:
#   mynet:
#     external: true
```

### Pod shared namespace networking

When containers are in the same Pod, they share:
- Network namespace (same IP, communicate via localhost)
- UTS namespace (hostname)
- IPC namespace

```bash
# Create a pod (containers share localhost)
podman pod create --name mypod -p 8080:80

# Add containers to pod (no -p needed — port is on the pod)
podman run -d --pod mypod --name frontend nginx
podman run -d --pod mypod --name backend myapp

# frontend can reach backend via http://localhost:8080
```

### Network with compose.yaml

```yaml
services:
  app:
    image: myapp:latest
    networks:
      - frontend
      - backend
  db:
    image: postgres:16
    networks:
      - backend

networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge
    internal: true  # No external access
```

---

## Volumes

### Named volumes

```bash
# Create a named volume
podman volume create mydata

# List volumes
podman volume ls

# Inspect volume
podman volume inspect mydata

# Use volume
podman run -d -v mydata:/data myapp:latest

# Remove volume
podman volume rm mydata
```

### Bind mounts with SELinux

On openSUSE Leap 16 with SELinux, you **must** add SELinux labels:

```bash
# :z — shared label (multiple containers can read/write)
podman run -v /host/path:/container/path:z myapp

# :Z — private label (only this container can access)
podman run -v /host/path:/container/path:Z myapp

# Without :z or :Z, SELinux will block access
```

### Volume in compose.yaml

```yaml
services:
  app:
    volumes:
      # Named volume
      - appdata:/data
      # Bind mount with SELinux label
      - ./config:/app/config:z
      # Read-only bind mount
      - ./static:/app/static:ro,z

volumes:
  appdata:
    driver: local
```

### Volume in Quadlet

```ini
[Container]
Volume=/var/lib/suse-ai:/data:rw,z
Volume=myapp-config:/app/config:rw
```

---

## Image Management

### Building images

```bash
# Build with Containerfile (recommended name) or Dockerfile
podman build -t myapp:latest .

# Build with build arguments
podman build --build-arg VERSION=1.0 -t myapp:1.0 .

# Build without cache
podman build --no-cache -t myapp:latest .

# Build for multi-architecture
podman build --manifest myapp:latest --platform linux/amd64,linux/arm64 .

# Build with Buildah (advanced)
buildah bud -t myapp:latest .
```

### Pushing and pulling

```bash
# Pull from registry
podman pull docker.io/library/nginx:latest
podman pull registry.opensuse.org/opensuse/leap:16

# Tag for push
podman tag myapp:latest registry.example.com/myapp:v1.0

# Push to registry (supports Docker Hub, GHCR, Quay, etc.)
podman push registry.example.com/myapp:v1.0

# Push to local registry
podman tag myapp:latest localhost/myapp:latest
podman push localhost/myapp:latest

# Login to registry
podman login registry.example.com
podman login docker.io
```

### Image management commands

```bash
# List local images
podman images

# Inspect image
podman inspect myapp:latest

# Image history
podman history myapp:latest

# Remove image
podman rmi myapp:latest

# Remove dangling images
podman image prune

# Remove all unused images
podman image prune -a

# Save/load images (tar archive)
podman save myapp:latest -o myapp.tar
podman load -i myapp.tar

# Copy images between registries with Skopeo
skopeo copy docker://source/registry/image:tag docker://dest/registry/image:tag
```

---

## Security

### Capabilities

```bash
# Drop all capabilities (most secure)
podman run --cap-drop ALL myapp:latest

# Drop specific capability
podman run --cap-drop NET_RAW myapp:latest

# Add specific capability
podman run --cap-add NET_BIND_SERVICE myapp:latest

# List capabilities in running container
podman run --rm alpine capsh --print
```

### Seccomp profiles

```bash
# Use default seccomp profile (default)
podman run --security-opt seccomp=default.json myapp

# Use custom seccomp profile
podman run --security-opt seccomp=/path/to/profile.json myapp

# Disable seccomp (NOT recommended)
podman run --security-opt seccomp=unconfined myapp
```

### SELinux on openSUSE

```bash
# Run with SELinux type (default on Leap 16)
podman run --security-opt label=type:container_t myapp

# Disable SELinux for this container (NOT recommended)
podman run --security-opt label=disable myapp

# Use :z/:Z on volume mounts for SELinux
podman run -v /data:/data:z myapp
```

### Read-only root filesystem

```bash
# Read-only root (more secure)
podman run --read-only --tmpfs /tmp --tmpfs /run myapp:latest

# In Quadlet
# [Container]
# ReadOnly=true
```

### Security best practices

```bash
# 1. Use rootless containers (default on Leap 16)
podman run --rm alpine whoami  # Runs as your user

# 2. Drop all capabilities
podman run --cap-drop ALL --cap-add NET_BIND_SERVICE myapp

# 3. Read-only filesystem
podman run --read-only --tmpfs /tmp myapp

# 4. No new privileges
podman run --security-opt no-new-privileges:true myapp

# 5. Resource limits
podman run --memory=2g --cpus=2 myapp

# 6. Use --userns=keep-id for consistent UID mapping
podman run --userns=keep-id myapp

# 7. Scan images for vulnerabilities
podman image trust set --type accept docker.io/library/nginx
```

---

## Podman Pods

Pods group containers that share network, IPC, and UTS namespaces — just like
Kubernetes pods.

### Creating and managing pods

```bash
# Create a pod
podman pod create --name mypod -p 8080:80

# List pods
podman pod ls

# Inspect pod
podman pod inspect mypod

# Add container to pod
podman run -d --pod mypod --name web nginx
podman run -d --pod mypod --name api myapp:latest

# Containers in the pod share:
# - Network namespace (same IP, communicate via localhost)
# - IPC namespace
# - UTS namespace (hostname)

# Stop all containers in pod
podman pod stop mypod

# Remove pod (and all containers in it)
podman pod rm mypod

# Generate Kubernetes YAML from pod
podman generate kube mypod > mypod.yaml

# Play Kubernetes YAML
podman play kube mypod.yaml
```

### Pod with compose.yaml

```yaml
services:
  frontend:
    image: nginx:latest
  backend:
    image: myapp:latest
    depends_on:
      frontend:
        condition: service_started

# Pod is implicit when using compose —
# or use Quadlet .pod files for explicit pod control
```

### Pod with Quadlet

```ini
# suse-ai-pod.pod
[Pod]
PublishPort=8090:8090

# Then reference in container files:
# [Container]
# Pod=suse-ai-pod
```

---

## Troubleshooting

### Common issues and solutions

#### 1. "Cannot connect to Podman" or missing `podman.service`

**Problem:** Scripts look for a Podman daemon service.

**Solution:** Podman is daemonless. Remove any `Wants=podman.service`,
`After=podman.service`, or `BindsTo=podman.service` from systemd units.

#### 2. `Type=notify` causes timeout

**Problem:** Service unit uses `Type=notify` but Podman doesn't support sd_notify.

**Solution:** Use `Type=simple` in all Podman-related systemd units.

#### 3. Port < 1024 binding fails rootless

**Problem:** `podman run -p 80:8080 myapp` fails with permission denied.

**Solutions:**
```bash
# Option A: Use higher ports (recommended)
podman run -p 8080:80 myapp

# Option B: Allow unprivileged port binding
sudo sysctl net.ipv4.ip_unprivileged_port_start=80

# Option C: Forward with systemd socket (runs as root)
```

#### 4. SELinux blocks volume access

**Problem:** Container cannot read/write mounted volume.

**Solution:** Add SELinux labels to volume mounts:
```bash
podman run -v /data:/data:z myapp   # Shared label
podman run -v /data:/data:Z myapp   # Private label
```

#### 5. Rootless overlay not working

**Problem:** Overlay driver fails on certain filesystems (e.g., NFS, XFS without ftype).

**Solutions:**
```bash
# Install fuse-overlayfs
sudo zypper install fuse-overlayfs

# Configure rootless storage
# ~/.config/containers/storage.conf
[storage]
driver = "overlay"
[storage.options]
overlay.mount_program = "/usr/bin/fuse-overlayfs"
```

#### 6. User services don't persist after logout

**Problem:** `systemctl --user` services stop when you log out.

**Solution:** Enable lingering:
```bash
loginctl enable-linger $(whoami)
```

#### 7. `podman compose` not found

**Problem:** Command not found on older systems.

**Solution:** On Leap 16, `podman compose` is built-in. If missing:
```bash
sudo zypper install podman
# Do NOT install docker-compose or podman-compose
```

#### 8. Docker-compose scripts fail

**Problem:** Scripts call `docker-compose` which doesn't exist.

**Solution:**
```bash
# Option A: Install podman-docker for docker CLI compat
sudo zypper install podman-docker

# Option B: Create alias
alias docker-compose='podman compose'

# Option C: Use podman compose directly
podman compose up -d
```

---

## Command Reference

> See [`podman-commands.md`](./podman-commands.md) for the complete CLI reference
> organized by category (50+ commands).

### Quick reference

```bash
# === Container lifecycle ===
podman run        # Run a container
podman ps         # List running containers
podman ps -a      # List all containers
podman stop       # Stop containers
podman start      # Start stopped containers
podman restart    # Restart containers
podman rm         # Remove containers
podman exec       # Execute command in container
podman logs       # View container logs
podman inspect    # Inspect container/image/volume
podman wait       # Wait for container to stop

# === Images ===
podman build      # Build image from Containerfile
podman pull       # Pull image from registry
podman push       # Push image to registry
podman images     # List local images
podman rmi        # Remove image
podman tag        # Tag an image
podman save       # Save image to tar
podman load       # Load image from tar

# === Compose ===
podman compose up         # Start compose services
podman compose down       # Stop compose services
podman compose logs       # View compose logs
podman compose ps         # List compose containers
podman compose build      # Build compose images

# === Pods ===
podman pod create         # Create a pod
podman pod ls             # List pods
podman pod rm             # Remove pod
podman pod stop           # Stop pod
podman pod start          # Start pod
podman generate kube      # Generate Kubernetes YAML

# === System ===
podman system info        # Show system info
podman system prune       # Remove unused data
podman system migrate     # Migrate containers to new version
podman info               # Display system information

# === Volumes ===
podman volume create      # Create volume
podman volume ls          # List volumes
podman volume rm          # Remove volume
podman volume inspect     # Inspect volume

# === Networks ===
podman network create     # Create network
podman network ls         # List networks
podman network rm         # Remove network

# === Machine (optional, not needed on Leap 16) ===
podman machine init       # Create VM (macOS/Windows)
podman machine start      # Start VM
```

---

## Quick Start Checklist

```bash
# 1. Verify Podman is installed
podman --version

# 2. Test rootless operation
podman run --rm alpine echo "Podman works!"

# 3. Build your image
podman build -t suse-ai:latest -f Containerfile .

# 4. Option A: Run with Quadlet (recommended)
mkdir -p ~/.config/containers/systemd/
cp suse-ai.container suse-ai-pod.pod ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user enable --now suse-ai-pod suse-ai
loginctl enable-linger $(whoami)

# 4. Option B: Run with compose
podman compose up -d

# 4. Option C: Run directly
podman run -d --name suse-ai -p 8090:8090 --userns=keep-id localhost/suse-ai:latest

# 5. Verify
podman ps
curl http://localhost:8090
```

---

*Last updated: March 2026 — openSUSE Leap 16 with Podman 5.4.2*
