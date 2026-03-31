# openSUSE Build Service (OBS) Packaging Guide
# =============================================================================
# How to package suse-ai as an RPM using the openSUSE Build Service.
# Covers both Leap 15.x and Leap 16.x targets.
#
# Reference:
#   https://openbuildservice.org/
#   https://en.opensuse.org/Portal:How_to_contribute_to_openSUSE
#   https://build.opensuse.org/
# =============================================================================

## 1. Create an OBS Account

```
1. Go to: https://build.opensuse.org/
2. Click "Sign Up" → Create account (or login with openSUSE account)
3. Confirm your email
4. Generate an API key: Home → Configuration → API Token
```

## 2. Install osc (OBS Command-Line Client)

```bash
# On openSUSE Leap 16:
sudo zypper install -y osc

# On openSUSE Leap 15.x:
sudo zypper install -y osc

# Verify:
osc --version
osc help
```

## 3. Configure osc

```bash
# Create config file
cat > ~/.oscrc << 'EOF'
[general]
apiurl = https://api.opensuse.org
# Uncomment and set your credentials:
# user = your_username
# pass = your_api_token

# Enable check_libc, check_library, check_permissions by default
checkout_no_colon = 1
EOF

chmod 600 ~/.oscrc
```

## 4. Create a Home Project

```bash
# Create a project (private by default)
osc api -X POST /source/home:yourusername/_meta \
  -T <project>
<project name="home:yourusername:suse-ai">
  <title>SUSE AI Assistant</title>
  <description>
    AI-powered local assistant for openSUSE system onboarding.
    Runs a Small Language Model (SLM) with RAG over openSUSE documentation.
  </description>
</project>
EOF

# Or create via web UI:
# https://build.opensuse.org/project/new
```

## 5. Add Build Targets

```bash
# For Leap 16:
osc api -X POST /source/home:yourusername:suse-ai/_meta \
  --data '<repository name="openSUSE_Leap_16.0">
    <path project="openSUSE:Leap:16.0" repository="standard"/>
    <arch>x86_64</arch>
    <arch>aarch64</arch>
  </repository>'

# For Leap 15.6:
osc api -X POST /source/home:yourusername:suse-ai/_meta \
  --data '<repository name="openSUSE_Leap_15.6">
    <path project="openSUSE:Leap:15.6" repository="standard"/>
    <arch>x86_64</arch>
    <arch>aarch64</arch>
  </repository>'

# For Tumbleweed (rolling release):
osc api -X POST /source/home:yourusername:suse-ai/_meta \
  --data '<repository name="openSUSE_Tumbleweed">
    <path project="openSUSE:Factory" repository="snapshot"/>
    <arch>x86_64</arch>
    <arch>aarch64</arch>
  </repository>'
```

## 6. Create a Package

```bash
# Checkout the project
osc checkout home:yourusername:suse-ai
cd home:yourusername:suse-ai

# Create the suse-ai package
mkdir suse-ai
cd suse-ai

# Add files to OBS
osc add suse-ai.spec
osc add suse-ai.changes
# Add your source tarball:
#   tar czf suse-ai-0.1.0.tar.gz -C .. --transform 's/^suse-ai-deploy/suse-ai-0.1.0/' suse-ai-deploy/
#   osc add suse-ai-0.1.0.tar.gz

# Commit
osc commit -m "Initial package submission"
```

## 7. Create Source Tarball

```bash
# From your project root:
cd /path/to/suse-ai-deploy/

# Create the tarball (rename dir to match version)
cd ..
tar czf suse-ai-0.1.0.tar.gz \
  --transform 's/^suse-ai-deploy/suse-ai-0.1.0/' \
  suse-ai-deploy/ \
  --exclude='suse-ai-deploy/.git' \
  --exclude='suse-ai-deploy/__pycache__' \
  --exclude='suse-ai-deploy/*.egg-info'

# Verify contents
tar tzf suse-ai-0.1.0.tar.gz | head -20

# Add to OBS
cp suse-ai-0.1.0.tar.gz home:yourusername:suse-ai/suse-ai/
cd home:yourusername:suse-ai/suse-ai/
osc add suse-ai-0.1.0.tar.gz
osc commit -m "Add source tarball"
```

## 8. Trigger a Build

```bash
# Build locally (test before submitting)
osc build openSUSE_Leap_16.0 x86_64

# Build remotely (on OBS servers)
osc rebuild openSUSE_Leap_16.0

# Watch build status
osc results
osc log openSUSE_Leap_16.0 x86_64

# Download build results
osc getbinaries openSUSE_Leap_16.0 x86_64
```

## 9. Submit to openSUSE Factory (Community Review)

```bash
# When ready for community review:
osc submitrequest --description "SUSE AI Assistant: Local SLM with RAG for openSUSE onboarding" \
  openSUSE:Factory suse-ai
```

## 10. Version Differences: Leap 15.x vs 16.x

| Aspect | Leap 15.x | Leap 16.x |
|--------|-----------|-----------|
| Python | python311 (default), python313 optional | python313 (default) |
| Podman | podman 4.x | podman 5.4.2 |
| systemd | systemd 254 | systemd 256 |
| Welcome | opensuse-welcome (Qt5) | opensuse-welcome-launcher + gnome-tour/plasma-welcome |
| Installer | YaST | Agama |
| SELinux | Optional (AppArmor default) | SELinux (AppArmor deprecated) |
| OBS Target | openSUSE:Leap:15.6 | openSUSE:Leap:16.0 |

### Conditional spec file for both versions:

```specfile
# In your .spec file, use conditionals:
%if 0%{?suse_version} >= 1600
# Leap 16.x specific
BuildRequires:  python313-devel
BuildRequires:  python313-textual
%else
# Leap 15.x specific
BuildRequires:  python3-devel >= 3.11
BuildRequires:  python311-textual || python3-textual
%endif
```

## 11. CI/CD: Automated Builds with OBS Services

```bash
# Add _service file for automated source generation
cat > _service << 'EOF'
<services>
  <service name="tar_scm" mode="localonly">
    <param name="scm">git</param>
    <param name="url">https://github.com/openSUSE/suse-ai.git</param>
    <param name="revision">main</param>
    <param name="filename">suse-ai</param>
    <param name="versionformat">0.1.0+git.%h</param>
  </service>
  <service name="recompress" mode="localonly">
    <param name="file">*.tar</param>
    <param name="compression">gz</param>
  </service>
  <service name="set_version" mode="localonly">
    <param name="basename">suse-ai</param>
  </service>
</services>
EOF

osc add _service
osc commit -m "Add _service for automated tarball generation"
```

## 12. Testing Your RPM Locally

```bash
# After osc getbinaries:
sudo zypper install ./suse-ai-0.1.0-0.x86_64.rpm

# Verify installation:
rpm -ql suse-ai            # List installed files
rpm -qi suse-ai            # Package info
systemctl status suse-ai.socket
ls /usr/share/suse-ai/
ls /var/lib/suse-ai/
```
