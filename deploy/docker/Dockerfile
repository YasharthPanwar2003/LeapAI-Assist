# =============================================================================
# SUSE AI Assistant — Production Dockerfile
# Base: openSUSE Leap 16
# Python: 3.13 (python313)
# Build:  multi-stage (builder → python-deps → runtime)
# =============================================================================

# ---------------------------------------------------------------------------
# Stage 1: Builder — compile-time dependencies and build tools
# ---------------------------------------------------------------------------
FROM opensuse/leap:16 AS builder

# OCI image labels (applied to all stages)
LABEL org.opencontainers.image.vendor="SUSE"
LABEL org.opencontainers.image.title="SUSE AI Assistant"
LABEL org.opencontainers.image.description="AI-powered assistant for openSUSE Leap 16"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.source="https://github.com/SUSE/suse-ai-deploy"
LABEL org.opencontainers.image.licenses="MIT"

# Install build dependencies
RUN zypper -n refresh && \
    zypper -n install --no-recommends \
        gcc \
        gcc-c++ \
        make \
        cmake \
        libopenssl-devel \
        python313-devel \
        pkg-config \
    && zypper -n clean -a && \
    rm -rf /var/cache/zypp/*

# ---------------------------------------------------------------------------
# Stage 2: python-deps — install Python dependencies into a virtualenv
# ---------------------------------------------------------------------------
FROM builder AS python-deps

# Install uv for fast pip installs
RUN zypper -n refresh && \
    zypper -n install --no-recommends \
        python313-pip \
        python313-venv \
    && zypper -n clean -a && \
    rm -rf /var/cache/zypp/*

# Install uv (Astral's fast Python package installer)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /build

# Create virtualenv with Python 3.13
RUN uv venv /opt/venv --python python3.13

# Enable virtualenv
ENV PATH="/opt/venv/bin:${PATH}"
ENV VIRTUAL_ENV="/opt/venv"

# Copy requirements and install dependencies
COPY requirements.txt .
RUN uv pip install --no-cache-dir --requirement requirements.txt

# ---------------------------------------------------------------------------
# Stage 3: Runtime — minimal production image
# ---------------------------------------------------------------------------
FROM opensuse/leap:16 AS runtime

# Labels (override from builder stages)
LABEL org.opencontainers.image.vendor="SUSE"
LABEL org.opencontainers.image.title="SUSE AI Assistant (runtime)"
LABEL org.opencontainers.image.description="Runtime image for the SUSE AI Assistant"
LABEL org.opencontainers.image.version="1.0.0"

# Install runtime-only dependencies
RUN zypper -n refresh && \
    zypper -n install --no-recommends \
        python313 \
        python313-base \
        ca-certificates-mozilla \
        curl \
        libcurl4 \
        glibc-locale \
        timezone \
        shadow \
    && zypper -n clean -a && \
    rm -rf /var/cache/zypp/*

# Create non-root user and group
RUN groupadd -r appuser -g 1000 && \
    useradd -r -m -u 1000 -g appuser -s /usr/sbin/nologin \
        -c "SUSE AI Assistant" appuser

# Copy virtualenv from python-deps stage
COPY --from=python-deps /opt/venv /opt/venv

# Set environment
ENV PATH="/opt/venv/bin:${PATH}" \
    VIRTUAL_ENV="/opt/venv" \
    PYTHONUNBUFFERED="1" \
    PYTHONDONTWRITEBYTECODE="1" \
    LANG="en_US.UTF-8" \
    LC_ALL="en_US.UTF-8" \
    TZ="UTC"

# Create application directory
WORKDIR /app

# Copy application code
COPY --chown=appuser:appuser . .

# Create data and cache directories
RUN mkdir -p /app/data /app/cache && \
    chown -R appuser:appuser /app/data /app/cache

# Expose the application port
EXPOSE 8090

# Health check — verify the app responds on port 8090
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -fs http://localhost:8090/health || exit 1

# Drop to non-root user
USER appuser

# Run the application
ENTRYPOINT ["python3.13"]
CMD ["-m", "suse_ai_assistant.main"]
