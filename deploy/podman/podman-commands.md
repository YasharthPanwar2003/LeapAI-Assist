# Podman CLI — Complete Command Reference

> Podman 5.4.2 on openSUSE Leap 16 | 50+ commands organized by category

---

## Table of Contents

1. [Container Lifecycle](#container-lifecycle)
2. [Container Execution](#container-execution)
3. [Container Inspection](#container-inspection)
4. [Images](#images)
5. [Volumes](#volumes)
6. [Networks](#networks)
7. [Pods](#pods)
8. [Compose](#compose)
9. [System & Maintenance](#system--maintenance)
10. [Kubernetes Integration](#kubernetes-integration)
11. [Security & Trust](#security--trust)
12. [Machine (macOS/Windows)](#machine-macoswindows)
13. [Quadlet & systemd](#quadlet--systemd)
14. [Utility Commands](#utility-commands)
15. [Global Options](#global-options)
16. [Differences from Docker CLI](#differences-from-docker-cli)

---

## Container Lifecycle

### `podman run`

Create and run a new container.

```bash
# Basic run
podman run --rm alpine echo "Hello World"

# Run in background (detached)
podman run -d --name myapp nginx:latest

# Interactive with TTY
podman run -it alpine /bin/sh

# With port mapping
podman run -d -p 8080:80 nginx

# With volume mount (SELinux label required on Leap 16)
podman run -d -v /host/data:/container/data:z myapp

# With environment variables
podman run -d -e DB_HOST=localhost -e DB_PORT=5432 myapp

# With memory and CPU limits
podman run -d --memory=2g --cpus=2 myapp

# Rootless with user namespace mapping
podman run -d --userns=keep-id -v /data:/data:z myapp

# With health check
podman run -d \
  --healthcheck-command "curl -sf http://localhost:8080/health" \
  --healthcheck-interval 30s \
  --healthcheck-timeout 5s \
  --healthcheck-retries 3 \
  myapp

# Remove automatically on exit
podman run --rm alpine cat /etc/os-release

# Privileged (NOT recommended — breaks rootless security)
podman run --privileged alpine
```

**Common flags:**

| Flag | Description |
|---|---|
| `-d, --detach` | Run in background |
| `--rm` | Remove container after exit |
| `-it` | Interactive + TTY |
| `--name` | Container name |
| `-p, --publish` | Port mapping (host:container) |
| `-v, --volume` | Volume mount |
| `-e, --env` | Environment variable |
| `--env-file` | Environment file |
| `--userns` | User namespace mode (`keep-id` for rootless) |
| `--network` | Network to connect |
| `--hostname` | Container hostname |
| `--memory` | Memory limit |
| `--cpus` | CPU limit |
| `--cap-drop` | Drop capability |
| `--cap-add` | Add capability |
| `--read-only` | Read-only root filesystem |
| `--restart` | Restart policy (`no`, `on-failure`, `always`) |
| `--security-opt` | Security options |
| `--label` | Container labels |
| `--workdir, -w` | Working directory |
| `--entrypoint` | Override entrypoint |
| `--privileged` | Full privileges (NOT recommended) |
| `--pid` | PID namespace (`host` for shared) |
| `--ipc` | IPC namespace |
| `--uts` | UTS namespace |

### `podman ps`

List containers.

```bash
# List running containers
podman ps

# List all containers (including stopped)
podman ps -a

# Custom format
podman ps --format "{{.ID}} {{.Names}} {{.Status}} {{.Ports}}"

# Filter by status
podman ps --filter status=running
podman ps --filter status=exited

# Filter by label
podman ps --filter label=app=suse-ai

# Show container IDs only
podman ps -q

# Show latest created container
podman ps -l

# Size information
podman ps -s
```

### `podman stop`

Stop one or more containers.

```bash
# Stop by name or ID
podman stop myapp
podman stop abc123def456

# Stop multiple
podman stop container1 container2 container3

# Stop all running containers
podman stop --all

# Graceful stop with timeout (default 10s)
podman stop -t 30 myapp
```

### `podman start`

Start stopped containers.

```bash
# Start a stopped container
podman start myapp

# Start with attach (see output)
podman start -a myapp

# Start multiple
podman start container1 container2

# Start all stopped containers
podman start --all

# Start with interactive TTY
podman start -ai myapp
```

### `podman restart`

Restart running containers.

```bash
podman restart myapp
podman restart -t 30 myapp
podman restart --all
```

### `podman rm`

Remove containers.

```bash
# Remove stopped container
podman rm myapp

# Force remove running container
podman rm -f myapp

# Remove all stopped containers
podman container prune

# Remove all containers (running and stopped)
podman rm -f $(podman ps -aq)

# Remove with volumes
podman rm -v myapp
```

### `podman kill`

Send signal to containers.

```bash
# Send SIGKILL
podman kill myapp

# Send specific signal
podman kill -s SIGTERM myapp

# Kill all running containers
podman kill --all
```

### `podman wait`

Wait for container to stop.

```bash
# Wait and print exit code
podman wait myapp

# Wait for multiple containers
podman wait container1 container2
```

### `podman pause` / `podman unpause`

Pause/unpause processes in a container.

```bash
podman pause myapp
podman unpause myapp
```

### `podman rename`

Rename a container.

```bash
podman rename old-name new-name
```

---

## Container Execution

### `podman exec`

Execute a command in a running container.

```bash
# Run command in container
podman exec myapp ls /app

# Interactive shell
podman exec -it myapp /bin/sh
podman exec -it myapp /bin/bash

# Run as specific user
podman exec -u root myapp cat /etc/shadow

# Set environment for command
podman exec -e MY_VAR=value myapp printenv MY_VAR

# Set working directory
podman exec -w /app myapp ls -la
```

### `podman attach`

Attach to a running container's stdin/stdout/stderr.

```bash
podman attach myapp

# Detach with Ctrl+P, Ctrl+Q
```

### `podman cp`

Copy files between host and container.

```bash
# Copy from host to container
podman cp file.txt myapp:/app/file.txt

# Copy from container to host
podman cp myapp:/app/output.txt ./output.txt

# Copy directory
podman cp ./localdir/ myapp:/app/remotedir/

# Preserve ownership and permissions
podman cp --chown 1000:1000 file.txt myapp:/app/
```

### `podman logs`

View container logs.

```bash
# View all logs
podman logs myapp

# Follow logs (like tail -f)
podman logs -f myapp

# Last N lines
podman logs --tail 100 myapp

# Show timestamps
podman logs -t myapp

# Since a specific time
podman logs --since 2026-03-01T00:00:00 myapp
podman logs --since 1h myapp

# Filter by time range
podman logs --since 10m --until 5m myapp
```

---

## Container Inspection

### `podman inspect`

Display detailed information about containers, images, volumes, networks, or pods.

```bash
# Inspect container
podman inspect myapp

# Inspect image
podman inspect nginx:latest

# Format output (Go template)
podman inspect --format '{{.State.Status}}' myapp
podman inspect --format '{{.Config.Image}}' myapp
podman inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' myapp

# JSON output
podman inspect --format '{{json .Config.Env}}' myapp | python3 -m json.tool

# Inspect multiple fields
podman inspect --format 'IP: {{.NetworkSettings.IPAddress}} Status: {{.State.Status}}' myapp

# Inspect volume
podman inspect myvolume

# Inspect network
podman inspect podman

# Inspect pod
podman inspect mypod
```

### `podman top`

Display running processes in a container.

```bash
podman top myapp

# Show specific columns
podman top myapp pid user args

# Show all available fields
podman top myapp -eo pid,user,comm,args
```

### `podman stats`

Display resource usage statistics.

```bash
# Live stats for all running containers
podman stats

# Stats for specific container
podman stats myapp

# One-shot (don't stream)
podman stats --no-stream myapp

# Custom format
podman stats --format "{{.Name}}: CPU={{.CPUPerc}} MEM={{.MemUsage}}"
```

### `podman port`

List port mappings.

```bash
podman port myapp
podman port myapp 80/tcp
```

### `podman diff`

Inspect changes to container filesystem.

```bash
podman diff myapp
# A = added, C = changed, D = deleted
```

---

## Images

### `podman build`

Build an image from a Containerfile (or Dockerfile).

```bash
# Build from current directory
podman build -t myapp:latest .

# Build with specific Containerfile path
podman build -t myapp:latest -f deploy/podman/Containerfile .

# Build with build arguments
podman build --build-arg VERSION=1.0 --build-arg BUILDKIT_INLINE_CACHE=1 -t myapp:1.0 .

# No cache
podman build --no-cache -t myapp:latest .

# Pull intermediate images (don't use cache)
podman build --pull=always -t myapp:latest .

# Multi-architecture build
podman build --manifest myapp:latest --platform linux/amd64,linux/arm64 .

# Build with Buildah (alternative)
buildah bud -t myapp:latest .

# Build with additional tags
podman build -t myapp:latest -t myapp:v1.0 -t registry.example.com/myapp:latest .

# Build with target stage
podman build --target runtime -t myapp:latest .
```

### `podman pull`

Pull an image from a registry.

```bash
# Pull from Docker Hub
podman pull nginx:latest
podman pull docker.io/library/nginx:latest

# Pull from openSUSE registry
podman pull registry.opensuse.org/opensuse/leap:16

# Pull all tags (manifest)
podman pull --all-tags alpine

# Pull with specific architecture
podman pull --platform linux/amd64 nginx:latest

# Pull with authentication
podman pull --creds username:password registry.example.com/myapp:latest
```

### `podman push`

Push an image to a registry.

```bash
# Push to Docker Hub
podman push myapp:latest docker.io/myuser/myapp:latest

# Push to custom registry
podman push myapp:latest registry.example.com/myapp:v1.0

# Push with authentication
podman push --creds username:password myapp:latest registry.example.com/myapp:latest

# Push manifest list
podman manifest push myapp:latest registry.example.com/myapp:latest
```

### `podman images` / `podman image ls`

List local images.

```bash
# List all images
podman images

# Show dangling images
podman images -f dangling=true

# Custom format
podman images --format "{{.Repository}}:{{.Tag}} {{.Size}}"

# Quiet (IDs only)
podman images -q

# Filter by reference
podman images --filter reference=localhost/*
```

### `podman rmi`

Remove one or more images.

```bash
# Remove image
podman rmi myapp:latest

# Force remove
podman rmi -f myapp:latest

# Remove all
podman rmi --all

# Remove dangling
podman image prune
podman image prune -f

# Remove all unused (dangling + unreferenced)
podman image prune -a
```

### `podman tag`

Tag an image.

```bash
# Create additional tag
podman tag myapp:latest myapp:v1.0

# Tag for registry push
podman tag myapp:latest registry.example.com/myuser/myapp:latest
```

### `podman save` / `podman load`

Save/load images as tar archives.

```bash
# Save single image
podman save myapp:latest -o myapp.tar

# Save multiple images
podman save myapp:latest myapp-db:latest -o images.tar

# Save with compression
podman save myapp:latest | gzip > myapp.tar.gz

# Load image from tar
podman load -i myapp.tar

# Load from stdin
podman load < myapp.tar.gz
```

### `podman history`

Show image history (layers).

```bash
podman history myapp:latest
podman history --no-trunc myapp:latest
podman history --format "{{.CreatedBy}}" myapp:latest
```

### `podman manifest`

Manage manifest lists (multi-architecture images).

```bash
# Create manifest
podman manifest create myapp:multi

# Add architecture variant
podman manifest add myapp:multi docker://myapp:amd64
podman manifest add myapp:multi docker://myapp:arm64

# Push manifest
podman manifest push myapp:multi docker://myuser/myapp:latest

# Inspect manifest
podman manifest inspect myapp:multi
```

### `podman image trust`

Manage image trust policies.

```bash
# Set trust for a registry
podman image trust set --type accept docker.io/library/nginx

# Show trust configuration
podman image trust show

# Remove trust
podman image trust remove docker.io/library/nginx
```

---

## Volumes

### `podman volume create`

```bash
# Create named volume
podman volume create mydata

# Create with driver options
podman volume create -d local -o o=size=10G mydata

# Create with label
podman volume create --label env=prod mydata
```

### `podman volume ls`

```bash
podman volume ls
podman volume ls -f label=env=prod
podman volume ls -q  # IDs only
```

### `podman volume inspect`

```bash
podman volume inspect mydata
podman volume inspect --format '{{.Mountpoint}}' mydata
```

### `podman volume rm`

```bash
podman volume rm mydata
podman volume prune  # Remove unused volumes
podman volume prune -f
```

---

## Networks

### `podman network create`

```bash
# Create bridge network
podman network create mynet

# With subnet
podman network create --subnet 10.89.0.0/24 mynet

# Internal network (no external access)
podman network create --internal mynet

# With gateway
podman network create --subnet 10.89.0.0/24 --gateway 10.89.0.1 mynet

# With DNS
podman network create --dns 8.8.8.8 mynet

# With IPv6
podman network create --ipv6 --subnet fd00::/64 mynet
```

### `podman network ls`

```bash
podman network ls
podman network ls -f name=mynet
podman network ls --no-trunc
```

### `podman network inspect`

```bash
podman network inspect mynet
podman network inspect --format '{{.Plugins.Bridge}}' mynet
```

### `podman network rm`

```bash
podman network rm mynet
podman network prune  # Remove unused networks
```

### `podman network connect` / `podman network disconnect`

```bash
# Connect running container to network
podman network connect mynet myapp

# Connect with alias
podman network connect --alias db mynet postgres

# Disconnect container from network
podman network disconnect mynet myapp
```

### `podman network reload`

Reload network configuration for a container.

```bash
podman network reload myapp
```

---

## Pods

### `podman pod create`

```bash
# Create pod
podman pod create --name mypod

# With port mapping
podman pod create --name mypod -p 8080:80

# With hostname
podman pod create --name mypod --hostname mypod

# With shared IPC
podman pod create --name mypod --share ipc
```

### `podman pod ls`

```bash
podman pod ls
podman pod ls --format "{{.Name}} {{.Status}} {{.InfraId}}"
```

### `podman pod inspect`

```bash
podman pod inspect mypod
podman pod inspect --format '{{.State.CgroupPath}}' mypod
```

### `podman pod rm`

```bash
podman pod rm mypod
podman pod rm --force mypod  # Remove even if containers are running
podman pod prune  # Remove all stopped pods
```

### `podman pod stop` / `podman pod start`

```bash
podman pod stop mypod
podman pod start mypod
podman pod stop --all
podman pod start --all
```

### `podman pod kill`

Send signal to all containers in a pod.

```bash
podman pod kill mypod
podman pod kill -s SIGTERM mypod
```

### `podman pod pause` / `podman pod unpause`

```bash
podman pod pause mypod
podman pod unpause mypod
```

### `podman pod logs`

View logs for containers in a pod.

```bash
podman pod logs mypod
podman pod logs -f mypod
podman pod logs --since 1h mypod
```

### `podman pod ps`

List containers in a pod.

```bash
podman pod ps --pod mypod
podman pod ps --pod mypod --format "{{.Name}} {{.Status}}"
```

### `podman pod restart`

```bash
podman pod restart mypod
```

### `podman pod stats`

Display resource usage for a pod.

```bash
podman pod stats mypod
```

### `podman pod top`

Display processes in all containers of a pod.

```bash
podman pod top mypod
```

---

## Compose

> Use `podman compose` (built-in since Podman 4.x). Do NOT use `docker-compose` or `podman-compose`.

### `podman compose up`

```bash
# Start all services
podman compose up -d

# Start with build
podman compose up -d --build

# Start specific services
podman compose up -d app db

# Start with profile
podman compose --profile monitoring up -d

# Start with force recreation
podman compose up -d --force-recreate

# Start with scale
podman compose up -d --scale app=3

# Start in foreground (see logs)
podman compose up
```

### `podman compose down`

```bash
# Stop and remove containers
podman compose down

# Remove volumes too
podman compose down -v

# Remove images too
podman compose down --rmi all

# Remove orphan containers
podman compose down --remove-orphans

# Stop without removing
podman compose stop
```

### `podman compose logs`

```bash
# All service logs
podman compose logs

# Follow logs
podman compose logs -f

# Specific service
podman compose logs app

# Last N lines
podman compose logs --tail 50

# With timestamps
podman compose logs -t
```

### `podman compose ps`

```bash
# List containers in compose project
podman compose ps

# With filters
podman compose ps --filter status=running
```

### `podman compose build`

```bash
# Build all services
podman compose build

# Build specific service
podman compose build app

# No cache
podman compose build --no-cache

# Pull base images
podman compose build --pull always
```

### `podman compose pull`

```bash
# Pull all service images
podman compose pull

# Pull specific service
podman compose pull app
```

### `podman compose exec`

```bash
# Execute command in service container
podman compose exec app ls /app
podman compose exec -it app /bin/sh
```

### `podman compose run`

```bash
# Run one-off command
podman compose run app python manage.py migrate

# Interactive
podman compose run -it app /bin/sh

# Remove after exit
podman compose run --rm app echo "done"
```

### `podman compose config`

```bash
# Validate and view merged configuration
podman compose config

# Output as JSON
podman compose config --format json
```

### `podman compose restart`

```bash
podman compose restart
podman compose restart app
```

### `podman compose stop` / `podman compose start`

```bash
podman compose stop
podman compose start
```

---

## System & Maintenance

### `podman system info`

```bash
# Show full system info
podman system info

# Format specific fields
podman system info --format '{{.Host.RemoteSocket.Path}}'
podman system info --format '{{.Host.Security.Rootless}}'
podman system info --format '{{.Plugins.Volume}}'
```

### `podman info`

```bash
podman info
podman info --format '{{.OperatingSystem}}'
```

### `podman system prune`

```bash
# Remove all unused data (containers, images, networks, build cache)
podman system prune

# Include volumes
podman system prune -a --volumes

# Force without confirmation
podman system prune -f
```

### `podman system migrate`

```bash
# Migrate containers to new Podman version
podman system migrate
```

### `podman system reset`

```bash
# Remove all Podman data (containers, images, volumes, networks)
# WARNING: Destructive!
podman system reset -f
```

### `podman system df`

```bash
# Show disk usage
podman system df

# Verbose
podman system df -v
```

### `podman system renumber`

```bash
# Renumber lock files (useful after manual lock file changes)
podman system renumber
```

### `podman cleanup` / `podman container prune` / `podman image prune`

```bash
# Remove stopped containers
podman container prune -f

# Remove unused images
podman image prune -f
podman image prune -a -f  # Remove all unreferenced

# Remove unused volumes
podman volume prune -f

# Remove unused networks
podman network prune -f

# Remove unused build cache
podman builder prune -f
```

### `podman login` / `podman logout`

```bash
# Login to registry
podman login docker.io
podman login registry.example.com
podman login --username myuser --password-stdin registry.example.com

# Logout
podman logout docker.io
```

---

## Kubernetes Integration

### `podman generate kube`

Generate Kubernetes YAML from existing Podman resources.

```bash
# Generate from a pod
podman generate kube mypod > mypod.yaml

# Generate from a container
podman generate kube mycontainer > mycontainer.yaml

# Include service definition
podman generate kube --service mypod > mypod-with-svc.yaml

# Include persistent volume claims
podman generate kube --podman-only mypod > mypod.yaml
```

### `podman play kube`

Deploy Kubernetes YAML with Podman.

```bash
# Deploy from YAML
podman play kube mypod.yaml

# Deploy from URL
podman play kube https://example.com/deployment.yaml

# Replace existing deployment
podman play kube --replace mypod.yaml

# Start with specific namespace
podman play kube --namespace myns mypod.yaml

# Tear down
podman play kube --down mypod.yaml
```

---

## Security & Trust

### `podman run` security flags

```bash
# Drop all capabilities (most secure)
podman run --cap-drop ALL myapp

# Add specific capability
podman run --cap-drop ALL --cap-add NET_BIND_SERVICE myapp

# No new privileges
podman run --security-opt no-new-privileges:true myapp

# Read-only root filesystem
podman run --read-only --tmpfs /tmp --tmpfs /run myapp

# Custom seccomp profile
podman run --security-opt seccomp=/path/to/profile.json myapp

# Disable seccomp (NOT recommended)
podman run --security-opt seccomp=unconfined myapp

# SELinux context
podman run --security-opt label=level:s0:c100,c200 myapp
podman run --security-opt label=disable myapp

# Mask paths (prevent access)
podman run --security-opt mask=/proc/self/mem myapp

# AppArmor profile
podman run --security-opt apparmor=myprofile myapp

# UID/GID mapping
podman run --userns=keep-id myapp
podman run --uidmap 0:100000:65536 --gidmap 0:100000:65536 myapp
```

### `podman secret`

```bash
# Create secret
echo "my-password" | podman secret create db-password -

# List secrets
podman secret ls

# Inspect secret
podman secret inspect db-password

# Use secret in container
podman run --secret db-password myapp

# Remove secret
podman secret rm db-password
```

---

## Machine (macOS/Windows)

> On openSUSE Leap 16, Podman runs natively — **Machine is NOT needed**.
> These commands are listed for cross-platform reference only.

```bash
# Initialize a VM (macOS/Windows only)
podman machine init

# Start VM
podman machine start

# Stop VM
podman machine stop

# List machines
podman machine ls

# SSH into machine
podman machine ssh

# Remove machine
podman machine rm
```

---

## Quadlet & systemd

### Deploying Quadlet units

```bash
# Copy Quadlet files to user config
mkdir -p ~/.config/containers/systemd/
cp *.container *.pod *.network *.volume ~/.config/containers/systemd/

# Reload systemd to generate units
systemctl --user daemon-reload

# Enable and start
systemctl --user enable --now myapp-pod
systemctl --user enable --now myapp

# Check generated units
ls /run/user/$(id -u)/systemd/generator/

# View status
systemctl --user status myapp

# View logs
journalctl --user -u myapp -f
```

### `podman generate systemd`

Generate systemd unit files from containers.

```bash
# Generate for existing container (creates new container on start)
podman generate systemd --name myapp --files --new

# Generate for existing container (manages existing container)
podman generate systemd --name myapp --files

# Output to stdout
podman generate systemd --name myapp
```

### `podman auto-update`

Auto-update containers based on policy.

```bash
# Apply auto-updates now
podman auto-update

# Register for systemd timer (one-time)
podman auto-update --register
```

---

## Utility Commands

### `podman version`

```bash
podman version
podman version --format '{{.Client.Version}}'
```

### `podman info`

```bash
podman info
podman info -f '{{.OperatingSystem}}'
```

### `podman events`

```bash
# Stream events
podman events

# Filter by type
podman events --filter type=container
podman events --filter type=image

# Filter by event
podman events --filter event=start
podman events --filter event=die

# Since/until
podman events --since 1h
podman events --since 2026-03-01T00:00:00 --until 2026-03-01T01:00:00
```

### `podman export` / `podman import`

```bash
# Export container filesystem as tar
podman export myapp > myapp.tar

# Import tar as image
podman import myapp.tar myapp-imported:latest

# Import with commit message
podman import --message "Exported from running container" myapp.tar myapp:v1
```

### `podman commit`

Create image from a container.

```bash
# Commit container as new image
podman commit myapp myapp-custom:latest

# With author and message
podman commit -a "admin@example.com" -m "Added custom config" myapp myapp-custom:latest

# With changes (RUN equivalent)
podman commit --change "ENV DEBUG=true" myapp myapp-debug:latest
```

### `podman mount` / `podman unmount`

```bash
# Mount container filesystem
podman mount myapp
podman mount  # List all mounts

# Unmount
podman unmount myapp
podman unmount --all
```

### `podman init`

Initialize a stopped container (set up for `podman start`).

```bash
podman init myapp
```

### `podman checkpoint` / `podman restore`

```bash
# Checkpoint running container
podman checkpoint myapp

# Checkpoint with keeping container running
podman checkpoint --keep myapp

# Restore from checkpoint
podman restore myapp
```

### `podman search`

Search for images on registries.

```bash
podman search nginx
podman search --filter is-official=true nginx
podman search --limit 5 python
```

### `podman farm`

Manage farms of container engines (Podman 4.x+).

```bash
# List farms
podman farm list

# Create farm
podman farm create myfarm host1.example.com host2.example.com
```

---

## Global Options

These options apply to all `podman` commands.

| Option | Description |
|---|---|
| `--help` | Show help |
| `--log-level` | Log level: `debug`, `info`, `warn`, `error`, `fatal` |
| `--log-file` | Log to file |
| `--storage-driver` | Storage driver (`overlay`, `vfs`, `fuse-overlayfs`) |
| `--storage-opt` | Storage driver options |
| `--cgroup-manager` | Cgroup manager (`systemd`, `cgroupfs`) |
| `--network-backend` | Network backend (`netavark`, `cni`) |
| `--events-backend` | Events backend (`journald`, `file`, `none`) |
| `--runtime` | OCI runtime (`runc`, `crun`, `kata`) |
| `--config` | Path to containers.conf |
| `--root` | Path to root directory |
| `--runroot` | Path to state directory |
| `--tmpdir` | Temporary directory |
| `--url` | URL to Podman service (for remote Podman) |

---

## Differences from Docker CLI

### Commands that work identically

```bash
podman run, podman ps, podman stop, podman start, podman rm
podman exec, podman logs, podman cp, podman pull, podman push
podman build, podman images, podman rmi, podman tag
podman network create, podman network ls, podman network rm
podman volume create, podman volume ls, podman volume rm
podman login, podman logout, podman search
```

### Commands unique to Podman

| Podman Command | Description |
|---|---|
| `podman pod` | Manage Kubernetes-compatible pods |
| `podman generate kube` | Generate Kubernetes YAML |
| `podman play kube` | Deploy Kubernetes YAML |
| `podman generate systemd` | Generate systemd units |
| `podman auto-update` | Auto-update containers |
| `podman machine` | Manage VMs (macOS/Windows) |
| `podman farm` | Manage remote engine farms |
| `podman secret` | Manage secrets |
| `podman checkpoint` / `podman restore` | CRIU checkpoint/restore |
| `podman quadlet` | Display Quadlet unit status |

### Commands NOT available in Podman

| Docker Command | Podman Equivalent |
|---|---|
| `docker swarm` | N/A (use Kubernetes: `podman play kube`) |
| `docker service` | N/A (use Kubernetes or Quadlet) |
| `docker stack` | N/A (use `podman play kube`) |
| `docker node` | N/A |
| `docker context` | `podman system connection` |

### Key behavioral differences

| Behavior | Docker | Podman |
|---|---|---|
| Default `--rm` | No | No (same) |
| Auto-restart | Via `restart:` in compose | Via Quadlet or `--restart` flag |
| daemon socket | `/var/run/docker.sock` | None (daemonless) |
| `docker compose` | Plugin | `podman compose` (built-in) |
| SELinux labels | Not needed (often) | **Required** on Leap 16 (`:z` / `:Z`) |

---

*Last updated: March 2026 — Podman 5.4.2 on openSUSE Leap 16*
