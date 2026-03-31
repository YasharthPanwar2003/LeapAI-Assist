# ============================================================================
# spec file for suse-ai
# ============================================================================
# openSUSE AI Assistant — Local SLM with RAG for system onboarding
# Platform: openSUSE Leap 15.x and 16.x
# Build:    osc build or rpmbuild -ba suse-ai.spec
# ============================================================================

Name:           suse-ai
Version:        0.1.0
Release:        0
Summary:        AI-powered local assistant for openSUSE system onboarding
License:        GPL-2.0-or-later
Group:          System/Management
URL:            https://github.com/openSUSE/suse-ai
Source0:        %{name}-%{version}.tar.gz

# ====================================================================
# Build Dependencies
# ====================================================================
BuildRequires:  python313-devel
BuildRequires:  python313-pip
BuildRequires:  podman
BuildRequires:  systemd

# ====================================================================
# Runtime Dependencies
# ====================================================================
Requires:       python313 >= 3.13
Requires:       podman >= 4.9
Requires:       systemd

# Optional: for the TUI
Recommends:     python313-textual
Recommends:     python313-rich

# Optional: for the web UI
Suggests:       python313-fastapi
Suggests:       python313-uvicorn

# Optional: for cockpit extension
Suggests:       cockpit

# ====================================================================
# Obsoletes/Conflicts
# ====================================================================
# If upgrading from an older version with different package name
Obsoletes:      suse-ai-assistant < 0.1.0
Provides:       suse-ai-assistant = %{version}-%{release}

# ====================================================================
# Description
# ====================================================================
%description
SUSE AI Assistant is a locally-running Small Language Model (SLM) integrated
with openSUSE's first-boot and onboarding experience. It provides interactive
guidance, command explanations, and troubleshooting insights by performing
retrieval-augmented generation (RAG) over official openSUSE documentation.

The assistant operates as a containerized service managed by systemd, using
Podman for rootless container execution. It activates lazily on first
connection via systemd socket activation, saving resources when idle.

%description -n suse-ai-welcome
Integration package for the openSUSE Welcome screen (opensuse-welcome-launcher
on Leap 16, opensuse-welcome on Leap 15.x). Adds a first-boot page that
guides users through enabling the AI assistant.

# ====================================================================
# Prep
# ====================================================================
%prep
%setup -q

# ====================================================================
# Build
# ====================================================================
%build
# Install Python dependencies (if building from source with pip)
# In production, dependencies should be RPM packages from OBS
pip3.13 install --root=%{buildroot} --prefix=/usr \
    --no-deps --no-compile \
    -r requirements-no-versions.txt 2>/dev/null || true

# ====================================================================
# Install
# ====================================================================
%install

# --- Application files ---
install -d -m 0755 %{buildroot}%{_datadir}/suse-ai
install -d -m 0755 %{buildroot}%{_datadir}/suse-ai/deploy
install -d -m 0755 %{buildroot}%{_datadir}/suse-ai/scripts
install -d -m 0755 %{buildroot}%{_datadir}/suse-ai/packaging

# Copy all source files
cp -r suse_ai/ %{buildroot}%{_datadir}/suse-ai/
cp -r deploy/ %{buildroot}%{_datadir}/suse-ai/deploy/
cp scripts/*.sh %{buildroot}%{_datadir}/suse-ai/scripts/ 2>/dev/null || true
cp scripts/*.py %{buildroot}%{_datadir}/suse-ai/scripts/ 2>/dev/null || true

# --- Config files ---
install -d -m 0755 %{buildroot}%{_sysconfdir}/suse-ai
install -m 0644 deploy/systemd/suse-ai.env %{buildroot}%{_sysconfdir}/suse-ai/env
install -m 0644 requirements.txt %{buildroot}%{_datadir}/suse-ai/
install -m 0644 requirements-no-versions.txt %{buildroot}%{_datadir}/suse-ai/

# --- Systemd units (system-wide) ---
install -d -m 0755 %{buildroot}%{_unitdir}
install -m 0644 deploy/systemd/suse-ai.socket %{buildroot}%{_unitdir}/
install -m 0644 deploy/systemd/suse-ai.service %{buildroot}%{_unitdir}/
install -m 0644 deploy/systemd/suse-ai-ingest.service %{buildroot}%{_unitdir}/
install -m 0644 deploy/systemd/suse-ai-ingest.timer %{buildroot}%{_unitdir}/

# --- JeOS firstboot module ---
install -d -m 0755 %{buildroot}%{_libexecdir}/jeos-firstboot/modules
install -m 0755 deploy/jeos-firstboot/04_ai_assistant.sh \
    %{buildroot}%{_libexecdir}/jeos-firstboot/modules/

# --- Data directories ---
install -d -m 0755 %{buildroot}%{_localstatedir}/lib/suse-ai
install -d -m 0755 %{buildroot}%{_localstatedir}/lib/suse-ai/models
install -d -m 0755 %{buildroot}%{_localstatedir}/lib/suse-ai/index
install -d -m 0755 %{buildroot}%{_localstatedir}/lib/suse-ai/cache
install -d -m 0755 %{buildroot}%{_localstatedir}/lib/suse-ai/logs

# --- Documentation ---
install -d -m 0755 %{buildroot}%{_docdir}/%{name}
install -m 0644 README.md %{buildroot}%{_docdir}/%{name}/
install -m 0644 LICENSE %{buildroot}%{_docdir}/%{name}/ 2>/dev/null || true

# --- Containerfile ---
install -d -m 0755 %{buildroot}%{_datadir}/suse-ai/deploy/podman
install -m 0644 Containerfile %{buildroot}%{_datadir}/suse-ai/deploy/podman/ 2>/dev/null || true
install -m 0644 compose.yaml %{buildroot}%{_datadir}/suse-ai/ 2>/dev/null || true

# ====================================================================
# Welcome subpackage install
# ====================================================================
%install -n suse-ai-welcome

# Welcome launcher integration files
install -d -m 0755 %{buildroot}%{_datadir}/suse-ai/deploy/opensuse-welcome
install -m 0644 deploy/opensuse-welcome/suse-ai-welcome.desktop \
    %{buildroot}%{_datadir}/suse-ai/deploy/opensuse-welcome/
install -m 0755 deploy/opensuse-welcome/suse-ai-welcome-setup \
    %{buildroot}%{_bindir}/suse-ai-welcome-setup

# Leap 16: gnome-tour JSON page
install -d -m 0755 %{buildroot}%{_datadir}/gnome-tour
install -m 0644 deploy/opensuse-welcome/suse-ai-tour.json \
    %{buildroot}%{_datadir}/gnome-tour/suse-ai.json

# Leap 15.x: opensuse-welcome JSON page
install -d -m 0755 %{buildroot}%{_datadir}/opensuse-welcome
install -m 0644 deploy/opensuse-welcome/suse-ai-tour.json \
    %{buildroot}%{_datadir}/opensuse-welcome/suse-ai.json

# Autostart entry (for Leap 16 desktop installs)
install -d -m 0755 %{buildroot}%{_sysconfdir}/xdg/autostart
install -m 0644 deploy/opensuse-welcome/suse-ai-welcome.desktop \
    %{buildroot}%{_sysconfdir}/xdg/autostart/

# ====================================================================
# Post-install
# ====================================================================
%post
%systemd_post suse-ai.socket
%systemd_post suse-ai-ingest.timer

%preun
%systemd_preun suse-ai.socket
%systemd_preun suse-ai-ingest.timer

%postun
%systemd_postun suse-ai.socket
%systemd_postun suse-ai-ingest.timer

# ====================================================================
# Welcome subpackage triggers
# ====================================================================
%post -n suse-ai-welcome
# Reload desktop database if available
update-desktop-database &>/dev/null || true

%postun -n suse-ai-welcome
update-desktop-database &>/dev/null || true

# ====================================================================
# Files
# ====================================================================
%files
# Application
%{_datadir}/suse-ai/
# Config
%config(noreplace) %{_sysconfdir}/suse-ai/env
# Systemd
%{_unitdir}/suse-ai.socket
%{_unitdir}/suse-ai.service
%{_unitdir}/suse-ai-ingest.service
%{_unitdir}/suse-ai-ingest.timer
# JeOS firstboot
%{_libexecdir}/jeos-firstboot/modules/04_ai_assistant.sh
# Data directories (owned by package)
%dir %{_localstatedir}/lib/suse-ai
%dir %{_localstatedir}/lib/suse-ai/models
%dir %{_localstatedir}/lib/suse-ai/index
%dir %{_localstatedir}/lib/suse-ai/cache
%dir %{_localstatedir}/lib/suse-ai/logs
# Documentation
%doc %{_docdir}/%{name}

%files -n suse-ai-welcome
%{_bindir}/suse-ai-welcome-setup
%{_datadir}/gnome-tour/suse-ai.json
%{_datadir}/opensuse-welcome/suse-ai.json
%{_sysconfdir}/xdg/autostart/suse-ai-welcome.desktop

# ====================================================================
# Changelog
# ====================================================================
%changelog
* Mon Mar 30 2026 - SUSE AI Team <suse-ai@opensuse.org>
- Initial version 0.1.0
- Containerized AI assistant with local SLM
- RAG pipeline over openSUSE documentation
- systemd socket activation (lazy start)
- jeos-firstboot module integration
- opensuse-welcome-launcher integration (Leap 16)
- Cockpit extension manifest
- Benchmark scripts for performance evaluation
- Deployment configs for Podman, Docker, K8s, Rancher
